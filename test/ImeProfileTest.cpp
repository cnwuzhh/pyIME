#include <RimeWithWeasel.h>
#include <WeaselUtility.h>
#include <iostream>
#include <rime_levers_api.h>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include <wincodec.h>
#include <windows.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

void Require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

bool HasExpectedSchemaOrder(const RimeSchemaList &schemas) {
  return schemas.size == 3 &&
         std::string(schemas.list[0].schema_id) == "luna_pinyin_simp" &&
         std::string(schemas.list[1].schema_id) == "luna_pinyin" &&
         std::string(schemas.list[2].schema_id) == "jaroomaji";
}

void VerifyWizardDefaults(RimeApi *api) {
  RimeModule *module = api->find_module("levers");
  Require(module && module->get_api, "Settings API is unavailable.");
  auto *levers = reinterpret_cast<RimeLeversApi *>(module->get_api());
  for (const std::string name : {"default", "weasel"}) {
    RimeCustomSettings *settings =
        levers->custom_settings_init(name.c_str(), "pyime.wizard.test");
    Require(settings && levers->load_settings(settings),
            "First-install settings could not be loaded.");
    RimeConfig config{};
    Require(levers->settings_get_config(settings, &config),
            "First-install settings configuration is unavailable.");
    if (name == "default") {
      char schema[128]{};
      Require(api->config_list_size(&config, "schema_list") == 3 &&
                  api->config_get_string(&config, "schema_list/@0/schema",
                                         schema, sizeof(schema)) &&
                  std::string(schema) == "luna_pinyin_simp",
              "First-install wizard did not select simplified Chinese.");
      Require(api->config_get_string(&config, "schema_list/@1/schema", schema,
                                     sizeof(schema)) &&
                  std::string(schema) == "luna_pinyin",
              "First-install wizard did not put traditional Pinyin second.");
      Require(api->config_get_string(&config, "schema_list/@2/schema", schema,
                                     sizeof(schema)) &&
                  std::string(schema) == "jaroomaji",
              "First-install wizard did not put Japanese third.");
    } else {
      weasel::UIStyle style;
      LoadWeaselUIStyle(&config, style);
      Require(style.layout_type == weasel::UIStyle::LAYOUT_HORIZONTAL &&
                  style.font_point == 14 &&
                  style.hilited_candidate_back_color == 0xFFD77800,
              "First-install wizard did not load the configured appearance.");
    }
    levers->custom_settings_destroy(settings);
  }
  RimeSwitcherSettings *switcher = levers->switcher_settings_init();
  auto *settings = reinterpret_cast<RimeCustomSettings *>(switcher);
  Require(settings && levers->load_settings(settings),
          "First-install switcher selection could not be loaded.");
  RimeSchemaList selected{};
  Require(levers->get_selected_schema_list(switcher, &selected),
          "First-install checked schemes are unavailable.");
  const bool selected_order = HasExpectedSchemaOrder(selected);
  levers->schema_list_destroy(&selected);
  levers->custom_settings_destroy(settings);
  Require(selected_order, "First-install checked schemes are not simplified, "
                          "traditional, Japanese.");
  std::cout
      << "PASS first-install checked schemes, order and appearance defaults\n";
}

struct Runtime {
  RimeApi *api = rime_get_api();
  Runtime(const char *shared, const char *user) {
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = shared;
    traits.user_data_dir = user;
    traits.prebuilt_data_dir = shared;
    traits.log_dir = user;
    traits.app_name = "pyime.profile.test";
    api->setup(&traits);
    api->deployer_initialize(&traits);
    VerifyWizardDefaults(api);
    api->initialize(&traits);
    if (api->start_maintenance(True))
      api->join_maintenance_thread();
    Require(api->deploy_config_file("weasel.yaml", "config_version"),
            "Weasel profile deployment failed.");
  }
  ~Runtime() { api->finalize(); }
};

void TapShift(RimeApi *api, RimeSessionId session, int key) {
  api->process_key(session, key, 1);
  api->process_key(session, key, 0x40000000);
}

void ExpectCommit(RimeApi *api, RimeSessionId session,
                  const std::string &expected) {
  RIME_STRUCT(RimeCommit, commit);
  Require(api->get_commit(session, &commit), "No text was committed.");
  const std::string actual = commit.text;
  api->free_commit(&commit);
  if (actual != expected)
    throw std::runtime_error("Committed text did not match; expected=" +
                             expected + ", actual=" + actual);
}

void VerifyShiftSwitching(RimeApi *api, RimeSessionId session) {
  for (int shift : {0xFFE1, 0xFFE2}) {
    TapShift(api, session, shift);
    Require(api->get_option(session, "ascii_mode"),
            "Shift did not switch to English.");
    Require(!api->process_key(session, 'x', 0),
            "English mode did not pass an ASCII letter to the application.");
    TapShift(api, session, shift);
    Require(!api->get_option(session, "ascii_mode"),
            "Shift did not switch back to Chinese.");
    Require(api->simulate_key_sequence(session, "nihao"),
            "Pending Pinyin input failed.");
    TapShift(api, session, shift);
    Require(api->get_option(session, "ascii_mode"),
            "Pending-input Shift did not select English.");
    ExpectCommit(api, session, "nihao");
    TapShift(api, session, shift);
    api->process_key(session, shift, 1);
    api->process_key(session, 'A', 1);
    api->process_key(session, shift, 0x40000000);
    Require(!api->get_option(session, "ascii_mode"),
            "Shift+letter incorrectly toggled input mode.");
    api->clear_composition(session);
    api->process_key(session, shift, 1);
    Sleep(550);
    api->process_key(session, shift, 0x40000000);
    Require(!api->get_option(session, "ascii_mode"),
            "Holding Shift incorrectly toggled input mode.");
  }
}

void ExpectCandidatePosition(RimeApi *api, RimeSessionId session, int page,
                             int highlighted) {
  RIME_STRUCT(RimeContext, context);
  Require(api->get_context(session, &context),
          "Candidate position is unavailable.");
  const bool matches = context.menu.page_no == page &&
                       context.menu.highlighted_candidate_index == highlighted;
  api->free_context(&context);
  Require(matches, "Candidate navigation moved to the wrong item or page.");
}

std::string RawInput(RimeApi *api, RimeSessionId session) {
  const char *input = api->get_input(session);
  Require(input != nullptr, "Raw input is unavailable.");
  return input;
}

void VerifyCandidateNavigation(RimeApi *api, RimeSessionId session,
                               const char *reading, const char *comma) {
  for (bool vertical : {false, true}) {
    for (bool linear : {false, true}) {
      api->set_option(session, "_vertical", vertical);
      api->set_option(session, "_linear", linear);
      Require(api->simulate_key_sequence(session, reading),
              "Candidate navigation reading failed.");
      ExpectCandidatePosition(api, session, 0, 0);
      Require(api->process_key(session, '.', 0),
              "Period did not select the next candidate.");
      ExpectCandidatePosition(api, session, 0, 1);
      Require(RawInput(api, session) == reading,
              "Next-candidate navigation modified the reading.");
      Require(api->process_key(session, ',', 0),
              "Comma did not select the previous candidate.");
      ExpectCandidatePosition(api, session, 0, 0);
      Require(api->process_key(session, '.', 0) &&
                  api->process_key(session, '.', 0),
              "Repeated candidate navigation failed.");
      ExpectCandidatePosition(api, session, 0, 2);
      Require(api->process_key(session, ',', 0),
              "Reverse candidate navigation failed.");
      ExpectCandidatePosition(api, session, 0, 1);
      RIME_STRUCT(RimeCommit, commit);
      const bool committed = api->get_commit(session, &commit);
      if (committed)
        api->free_commit(&commit);
      Require(!committed, "Candidate navigation committed text unexpectedly.");
      Require(api->process_key(session, 0xFF56, 0),
              "Page Down stopped working.");
      ExpectCandidatePosition(api, session, 1, 1);
      Require(api->process_key(session, 0xFF55, 0), "Page Up stopped working.");
      ExpectCandidatePosition(api, session, 0, 1);
      if (std::string(reading) == "zhongguo") {
        Require(api->process_key(session, '=', 0),
                "Equals stopped paging Chinese candidates.");
        ExpectCandidatePosition(api, session, 1, 1);
        Require(api->process_key(session, '-', 0),
                "Minus stopped paging Chinese candidates.");
        ExpectCandidatePosition(api, session, 0, 1);
      }
      api->clear_composition(session);
      Require(api->simulate_key_sequence(session, reading) &&
                  api->process_key(session, '.', 0) &&
                  api->process_key(session, 'a', 0),
              "Continuing input after candidate navigation failed.");
      Require(
          RawInput(api, session) == std::string(reading) + "a",
          "Candidate navigation inserted a period into the continued reading.");
      api->clear_composition(session);
    }
  }
  api->set_option(session, "_vertical", false);
  api->set_option(session, "_linear", false);
  Require(api->process_key(session, ',', 0),
          "Comma without a candidate menu stopped working.");
  ExpectCommit(api, session, comma);
  Require(api->process_key(session, '.', 0),
          "Period without a candidate menu stopped working.");
  ExpectCommit(api, session, u8"。");
  api->set_option(session, "ascii_mode", true);
  Require(!api->process_key(session, ',', 0) &&
              !api->process_key(session, '.', 0),
          "English punctuation was intercepted by candidate navigation.");
  api->set_option(session, "ascii_mode", false);
  std::cout << "PASS comma/period individual candidates, layout variants, "
               "paging, continuation and punctuation\n";
}

void VerifyJapaneseInput(RimeApi *api, RimeSessionId session,
                         const weasel::UIStyle &base_style) {
  Require(api->select_schema(session, "jaroomaji"),
          "Japanese scheme selection failed.");
  Require(!api->get_option(session, "ascii_mode"),
          "Japanese scheme must start in Japanese rather than English mode.");
  RimeConfig config{};
  Require(api->schema_open("jaroomaji", &config),
          "Japanese schema configuration is unavailable.");
  weasel::UIStyle style = base_style;
  LoadWeaselUIStyle(&config, style, false);
  api->config_close(&config);
  Require(style.font_face.find(L"Yu Gothic UI") != std::wstring::npos &&
              style.layout_type == weasel::UIStyle::LAYOUT_HORIZONTAL &&
              style.hilited_candidate_back_color ==
                  base_style.hilited_candidate_back_color,
          "Japanese must use Japanese font fallbacks and the same candidate "
          "style.");
  VerifyCandidateNavigation(api, session, "kanji", u8"、");
  for (const auto &example :
       {std::pair<const char *, const char *>{"hiragana", u8"ひらがな"},
        {"gakkou", u8"がっこう"}}) {
    Require(api->simulate_key_sequence(session, example.first),
            "Japanese romaji input failed.");
    Require(api->process_key(session, 0xFF0D, 0),
            "Enter did not confirm the Japanese kana composition.");
    ExpectCommit(api, session, example.second);
  }
  api->process_key(session, 0xFFE1, 1);
  for (char letter : std::string("KATAKANA")) {
    Require(api->process_key(session, letter, 1),
            "Shift+letter Japanese katakana input failed.");
  }
  api->process_key(session, 0xFFE1, 0x40000000);
  Require(!api->get_option(session, "ascii_mode"),
          "Typing Japanese katakana with Shift toggled English mode.");
  Require(api->process_key(session, 0xFF0D, 0),
          "Enter did not confirm the Japanese katakana.");
  ExpectCommit(api, session, u8"カタカナ");
  Require(api->simulate_key_sequence(session, "nihongo"),
          "Japanese kanji reading input failed.");
  RIME_STRUCT(RimeContext, context);
  Require(api->get_context(session, &context),
          "Japanese candidates are unavailable.");
  int candidate = -1;
  const bool five_per_page = context.menu.page_size == 5;
  for (int i = 0; i < context.menu.num_candidates; ++i) {
    if (std::string(context.menu.candidates[i].text) == u8"日本語")
      candidate = i;
  }
  api->free_context(&context);
  Require(
      five_per_page && candidate >= 0,
      "Japanese first-page candidates must contain the expected kanji word.");
  Require(api->process_key(session, '1' + candidate, 0),
          "Japanese kanji candidate selection failed.");
  ExpectCommit(api, session, u8"日本語");
  Require(api->simulate_key_sequence(session, "kanji"),
          "Japanese space-selection reading failed.");
  RIME_STRUCT(RimeContext, word);
  Require(api->get_context(session, &word),
          "Japanese word-selection candidates are unavailable.");
  int word_index = -1;
  for (int i = 0; i < word.menu.num_candidates; ++i) {
    if (std::string(word.menu.candidates[i].text) == u8"漢字")
      word_index = i;
  }
  api->free_context(&word);
  Require(word_index >= 0,
          "The expected Japanese homophone is missing from the first page.");
  for (int i = 0; i < word_index; ++i) {
    Require(api->process_key(session, 0xFF54, 0),
            "Down did not select the Japanese homophone.");
  }
  Require(api->process_key(session, ' ', 0),
          "Space did not confirm the Japanese candidate.");
  ExpectCommit(api, session, u8"漢字");
  Require(api->simulate_key_sequence(session, "nihongo"),
          "Japanese raw-letter confirmation input failed.");
  Require(api->process_key(session, 0xFF0D, 1),
          "Shift+Enter did not confirm the Japanese raw input.");
  ExpectCommit(api, session, "nihongo");
  Require(api->process_key(session, ',', 0), "Japanese comma input failed.");
  ExpectCommit(api, session, u8"、");
  Require(api->process_key(session, '.', 0), "Japanese period input failed.");
  ExpectCommit(api, session, u8"。");
  VerifyShiftSwitching(api, session);
  std::cout << "PASS Japanese hiragana, katakana, small tsu, kanji commit, "
               "punctuation and Shift English\n";
}

void SavePreview(weasel::UIStyle style, const weasel::Context &context,
                 const wchar_t *filename) {
  Require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)),
          "COM initialization failed.");
  struct ComScope {
    ~ComScope() { CoUninitialize(); }
  } com_scope;
  HWND backdrop = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, L"STATIC",
                                  L"pyIME Preview", WS_POPUP | SS_WHITERECT,
                                  100, 150, 900, 250, nullptr, nullptr,
                                  GetModuleHandleW(nullptr), nullptr);
  Require(backdrop != nullptr, "Preview backdrop creation failed.");
  ShowWindow(backdrop, SW_SHOWNOACTIVATE);
  UpdateWindow(backdrop);

  weasel::UI ui;
  ui.style() = style;
  Require(ui.Create(backdrop, true),
          "Native candidate window creation failed.");
  weasel::Status status;
  status.composing = true;
  status.schema_id = L"luna_pinyin_simp";
  ui.Update(context, status);
  ui.Show();
  RECT rect{};
  Require(GetWindowRect(ui.hwnd(), &rect),
          "Candidate window bounds unavailable.");
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  Require(width > height * 3 && width < 850 && height < 180,
          "Candidate window is not a bounded horizontal layout.");
  SetWindowPos(ui.hwnd(), HWND_TOPMOST, 120, 170, 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE);
  for (int i = 0; i < 30; ++i) {
    MSG message;
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
    Sleep(10);
  }
  RECT placed{};
  RECT background{};
  Require(GetWindowRect(ui.hwnd(), &placed) &&
              GetWindowRect(backdrop, &background) &&
              placed.left >= background.left && placed.top >= background.top &&
              placed.right <= background.right &&
              placed.bottom <= background.bottom,
          "Preview capture must remain inside its own backdrop.");

  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
  Require(screen && memory && bitmap, "Preview capture allocation failed.");
  HGDIOBJ previous = SelectObject(memory, bitmap);
  Require(BitBlt(memory, 0, 0, width, height, screen, placed.left, placed.top,
                 SRCCOPY),
          "Preview capture failed.");
  SelectObject(memory, previous);

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  std::vector<DWORD> pixels(static_cast<size_t>(width) * height);
  Require(GetDIBits(memory, bitmap, 0, height, pixels.data(), &info,
                    DIB_RGB_COLORS) == height,
          "Preview pixels could not be read.");
  size_t white = 0;
  size_t blue = 0;
  for (DWORD pixel : pixels) {
    const DWORD rgb = pixel & 0xFFFFFF;
    white += rgb == 0xFFFFFF;
    blue += rgb == 0x0078D7;
  }
  std::cout << "PREVIEW_PIXELS white=" << white << " blue=" << blue
            << " width=" << width << " height=" << height << '\n';

  ComPtr<IWICImagingFactory> factory;
  Require(
      SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))),
      "PNG factory creation failed.");
  ComPtr<IWICBitmap> image;
  Require(SUCCEEDED(factory->CreateBitmapFromHBITMAP(
              bitmap, nullptr, WICBitmapIgnoreAlpha, &image)),
          "Preview bitmap conversion failed.");
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> properties;
  Require(
      SUCCEEDED(factory->CreateStream(&stream)) &&
          SUCCEEDED(stream->InitializeFromFilename(filename, GENERIC_WRITE)) &&
          SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                           &encoder)) &&
          SUCCEEDED(
              encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) &&
          SUCCEEDED(encoder->CreateNewFrame(&frame, &properties)) &&
          SUCCEEDED(frame->Initialize(properties.Get())) &&
          SUCCEEDED(frame->WriteSource(image.Get(), nullptr)) &&
          SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit()),
      "Preview PNG export failed.");
  ui.Destroy(true);
  DestroyWindow(backdrop);
  Require(
      white > 1000 && blue > 100,
      "Native rendering did not contain white background and blue selection.");
  std::cout
      << "PASS native horizontal preview, white background, blue selection\n";
}

int main(int argc, char *argv[]) {
  try {
    Require(argc == 4 || argc == 5, "Expected shared-data user-data font-point "
                                    "[preview-png|--existing-selection].");
    Require(SetProcessDpiAwarenessContext(
                DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2),
            "DPI-aware native preview setup failed.");
    Runtime runtime(argv[1], argv[2]);
    RimeApi *api = runtime.api;
    const RimeSessionId session = api->create_session();
    Require(session != 0, "Session creation failed.");
    char schema[128]{};
    if (argc == 5 && std::string(argv[4]) == "--existing-selection") {
      Require(
          api->get_current_schema(session, schema, sizeof(schema)) &&
              std::string(schema) == "luna_pinyin",
          "An existing user's preferred traditional scheme was overridden.");
      RimeSchemaList selected{};
      Require(api->get_schema_list(&selected),
              "Existing user's selected schemes are unavailable.");
      const bool preserved =
          selected.size == 2 &&
          std::string(selected.list[0].schema_id) == "luna_pinyin" &&
          std::string(selected.list[1].schema_id) == "luna_pinyin_simp";
      api->free_schema_list(&selected);
      api->destroy_session(session);
      Require(preserved,
              "Existing user's scheme selection order was overridden.");
      std::cout << "PASS existing user's selected scheme order and default "
                   "preserved\n";
      return 0;
    }
    Require(api->get_current_schema(session, schema, sizeof(schema)) &&
                std::string(schema) == "luna_pinyin_simp",
            "The default scheme is not simplified Chinese.");
    Require(!api->get_option(session, "ascii_mode") &&
                api->get_option(session, "zh_hans"),
            "The initial session is not simplified Chinese input.");
    RimeSchemaList schemas{};
    Require(api->get_schema_list(&schemas), "Schema list unavailable.");
    const bool ordered_schemas = HasExpectedSchemaOrder(schemas);
    const bool named_schemas =
        schemas.size == 3 &&
        std::string(schemas.list[0].name) == u8"简体拼音" &&
        std::string(schemas.list[1].name) == u8"繁体拼音" &&
        std::string(schemas.list[2].name) == u8"日语";
    api->free_schema_list(&schemas);
    Require(ordered_schemas && named_schemas,
            "Expected named simplified, traditional and Japanese schemes in "
            "that order.");

    RimeConfig config{};
    Require(api->config_open("weasel", &config),
            "Compiled Weasel style unavailable.");
    weasel::UIStyle style;
    LoadWeaselUIStyle(&config, style);
    api->config_close(&config);
    Require(style.layout_type == weasel::UIStyle::LAYOUT_HORIZONTAL &&
                style.font_point == std::stoi(argv[3]) &&
                style.round_corner_ex == 8 && style.round_corner == 4 &&
                style.back_color == 0xFFFFFFFF &&
                style.hilited_candidate_back_color == 0xFFD77800,
            "The compiled native candidate style does not match the profile.");
    std::cout
        << "PASS default simplified scheme and compiled candidate style\n";

    Require(api->simulate_key_sequence(session, "zhongguo"),
            "Pinyin input failed.");
    RIME_STRUCT(RimeContext, context);
    Require(api->get_context(session, &context),
            "Candidate context unavailable.");
    Require(context.menu.page_size == 5 && context.menu.num_candidates == 5 &&
                std::string(context.menu.candidates[0].text) == u8"中国",
            "Simplified Chinese first candidate or page size is incorrect.");
    weasel::Context preview;
    preview.preedit.str = u8tow(context.composition.preedit);
    for (int i = 0; i < context.menu.num_candidates; ++i) {
      preview.cinfo.candies.emplace_back(
          u8tow(context.menu.candidates[i].text));
      preview.cinfo.comments.emplace_back(L"");
      preview.cinfo.labels.emplace_back(std::to_wstring(i + 1));
    }
    preview.cinfo.highlighted = context.menu.highlighted_candidate_index;
    preview.cinfo.is_last_page = context.menu.is_last_page;
    api->free_context(&context);
    Require(api->select_candidate_on_current_page(session, 0),
            "Candidate selection failed.");
    ExpectCommit(api, session, u8"中国");
    std::cout
        << "PASS simplified Chinese candidate, five-item page and commit\n";

    VerifyCandidateNavigation(api, session, "zhongguo", u8"，");
    VerifyShiftSwitching(api, session);
    Require(api->select_schema(session, "luna_pinyin"),
            "Traditional Pinyin selection failed.");
    Require(!api->get_option(session, "zh_hans") &&
                api->get_option(session, "zh_hant"),
            "Traditional Pinyin inherited simplified output mode.");
    Require(api->simulate_key_sequence(session, "zhongguo"),
            "Traditional Pinyin input failed.");
    RIME_STRUCT(RimeContext, traditional);
    Require(api->get_context(session, &traditional),
            "Traditional candidates unavailable.");
    const bool traditional_candidate =
        traditional.menu.num_candidates > 0 &&
        std::string(traditional.menu.candidates[0].text) == u8"中國";
    api->free_context(&traditional);
    Require(
        traditional_candidate,
        "Traditional Pinyin did not produce the expected traditional text.");
    Require(api->select_candidate_on_current_page(session, 0),
            "Traditional candidate selection failed.");
    ExpectCommit(api, session, u8"中國");
    VerifyCandidateNavigation(api, session, "zhongguo", u8"，");
    VerifyShiftSwitching(api, session);
    VerifyJapaneseInput(api, session, style);
    Require(
        api->select_schema(session, "luna_pinyin_simp") &&
            api->get_option(session, "zh_hans") &&
            !api->get_option(session, "zh_hant"),
        "Returning to simplified Pinyin did not restore simplified output.");
    std::cout << "PASS traditional Chinese commit and simplified/traditional "
                 "mode isolation\n";
    api->destroy_session(session);
    std::cout << "PASS Shift English switching in all three schemes, "
                 "pending-code commit and non-toggle gestures\n";
    if (argc == 5)
      SavePreview(style, preview, u8tow(argv[4]).c_str());
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
