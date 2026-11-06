using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

public sealed class ReleaseAsset
{
    public string name { get; set; }
    public long size { get; set; }
    public string state { get; set; }
    public string digest { get; set; }
    public string path { get; set; }
}

public sealed class ReleaseState
{
    public bool exists { get; set; }
    public bool draft { get; set; }
    public bool failAuth { get; set; }
    public bool badDigest { get; set; }
    public bool omitDigest { get; set; }
    public List<ReleaseAsset> assets { get; set; }
    public List<string> writes { get; set; }
}

public static class ReleaseCliStub
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string path = Environment.GetEnvironmentVariable("STELLAR_RELEASE_TEST_STATE");
        if (String.IsNullOrEmpty(path)) return Fail("Missing isolated test state.");
        var json = new JavaScriptSerializer();
        var state = json.Deserialize<ReleaseState>(File.ReadAllText(path));
        if (args.Length < 2) return Fail("Unsupported test CLI arguments.");
        if (args[0] == "api")
        {
            if (args.Contains("user")) return state.failAuth ? Fail("Simulated authentication failure.") : 0;
            if (args.Contains(".permissions.push")) { Console.WriteLine("true"); return 0; }
            if (args[1] == "graphql")
            {
                object release = state.exists ? new {
                    databaseId = 1, isDraft = state.draft, isPrerelease = false,
                    url = "https://github.com/cnwuzhh/pyIME/releases/tag/simulated-only"
                } : (object)null;
                Console.WriteLine(json.Serialize(new { data = new { repository = new { release = release } } }));
                return 0;
            }
            if (args[1] == "repos/cnwuzhh/pyIME/releases/1")
            {
                Console.WriteLine(json.Serialize(new { assets = state.assets }));
                return 0;
            }
        }
        if (args[0] == "release")
        {
            if (args[1] == "create")
            {
                if (state.exists || !args.Contains("--draft")) return Fail("Invalid draft creation.");
                state.exists = true;
                state.draft = true;
                state.writes.Add("create");
            }
            else if (args[1] == "upload")
            {
                if (!state.draft || args.Length < 4) return Fail("Upload must target a draft.");
                string file = args[3], name = Path.GetFileName(file);
                if (state.assets.Any(a => a.name == name)) return Fail("Asset overwrite attempted.");
                string hash;
                using (var sha = SHA256.Create())
                using (var stream = File.OpenRead(file))
                    hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
                state.assets.Add(new ReleaseAsset {
                    name = name, size = new FileInfo(file).Length, state = "uploaded", path = file,
                    digest = state.omitDigest ? null : "sha256:" + (state.badDigest ? new string('0', 64) : hash)
                });
                state.writes.Add("upload:" + name);
            }
            else if (args[1] == "edit")
            {
                if (!args.Contains("--draft=false") || !args.Contains("--prerelease=false") ||
                    !args.Contains("--latest=true") || state.assets.Count != 3)
                    return Fail("Publication must be stable and follow all three uploads.");
                state.draft = false;
                state.writes.Add("publish");
            }
            else if (args[1] == "download")
            {
                string name = Value(args, "--pattern"), destination = Value(args, "--dir");
                var asset = state.assets.Single(a => a.name == name);
                File.Copy(asset.path, Path.Combine(destination, name));
                state.writes.Add("download:" + name);
            }
            else return Fail("Unsupported release test command.");
            File.WriteAllText(path, json.Serialize(state), new UTF8Encoding(false));
            return 0;
        }
        return Fail("Unexpected test CLI command; no real GitHub request was made.");
    }

    private static string Value(string[] args, string flag)
    {
        int index = Array.IndexOf(args, flag);
        if (index < 0 || index + 1 >= args.Length) throw new ArgumentException(flag);
        return args[index + 1];
    }

    private static int Fail(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
