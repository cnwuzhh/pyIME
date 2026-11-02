#include <iostream>
#include <rime/config.h>
#include <rime_api.h>
#include <stdexcept>
#include <string>

int main(int argc, char *argv[]) {
  try {
    if (argc != 3)
      throw std::runtime_error("Expected data-directory profile-directory.");
    RIME_STRUCT(RimeTraits, traits);
    traits.app_name = "pyime.profile.build";
    traits.log_dir = ".";
    rime_get_api()->setup(&traits);
    for (const std::string name : {"default", "weasel", "luna_pinyin.schema",
                                   "luna_pinyin_simp.schema"}) {
      const rime::path base = rime::path(argv[1]) / (name + ".yaml");
      const rime::path patch_file =
          rime::path(argv[2]) / ("pyime." + name + ".yaml");
      rime::Config config;
      rime::Config patch;
      if (!config.LoadFromFile(base) || !patch.LoadFromFile(patch_file))
        throw std::runtime_error("Profile YAML could not be loaded: " + name);
      const auto values = patch.GetMap("patch");
      if (!values)
        throw std::runtime_error("Profile patch map is missing: " + name);
      // Enumerate via the exported C API; Get() preserves literal "/" in keys.
      RimeConfig patch_config{&patch};
      RimeConfigIterator entries{};
      RimeApi *api = rime_get_api();
      if (!api->config_begin_map(&entries, &patch_config, "patch"))
        throw std::runtime_error("Profile patch map is missing: " + name);
      while (api->config_next(&entries)) {
        const auto value = values->Get(entries.key);
        if (!value || !config.SetItem(entries.key, value))
          throw std::runtime_error("Profile setting could not be applied: " +
                                   std::string(entries.key));
      }
      api->config_end(&entries);
      if (!config.SaveToFile(base))
        throw std::runtime_error("Profile YAML could not be saved: " + name);
    }
    std::cout << "pyIME defaults materialized for the first-install wizard.\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
