using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class XingheBrandResources
{
    [DllImport("version.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetFileVersionInfoSize(string path, out int handle);
    [DllImport("version.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetFileVersionInfo(string path, int handle, int size, IntPtr data);
    [DllImport("version.dll", CharSet = CharSet.Unicode)]
    private static extern bool VerQueryValue(IntPtr data, string key, out IntPtr value, out uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);
    private delegate bool ResourceNameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);
    private delegate bool ResourceLanguageCallback(IntPtr module, IntPtr type, IntPtr name, ushort language, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumResourceNames(IntPtr module, IntPtr type, ResourceNameCallback callback, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, ResourceLanguageCallback callback, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindResourceEx(IntPtr module, IntPtr type, IntPtr name, ushort language);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);

    public static string[] VersionValues(string path, string field)
    {
        int handle;
        int size = GetFileVersionInfoSize(path, out handle);
        if (size == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), path);
        IntPtr data = Marshal.AllocHGlobal(size);
        try
        {
            if (!GetFileVersionInfo(path, 0, size, data))
                throw new Win32Exception(Marshal.GetLastWin32Error(), path);
            IntPtr translations;
            uint length;
            if (!VerQueryValue(data, @"\VarFileInfo\Translation", out translations, out length))
                throw new InvalidOperationException("No version translations: " + path);
            var result = new List<string>();
            for (int i = 0; i + 4 <= length; i += 4)
            {
                ushort language = unchecked((ushort)Marshal.ReadInt16(translations, i));
                ushort codepage = unchecked((ushort)Marshal.ReadInt16(translations, i + 2));
                string key = String.Format(@"\StringFileInfo\{0:x4}{1:x4}\{2}", language, codepage, field);
                IntPtr value;
                uint characters;
                if (!VerQueryValue(data, key, out value, out characters))
                    throw new InvalidOperationException("Missing " + field + " in " + path);
                result.Add(Marshal.PtrToStringUni(value));
            }
            if (result.Count == 0) throw new InvalidOperationException("Empty version translation list: " + path);
            return result.ToArray();
        }
        finally { Marshal.FreeHGlobal(data); }
    }

    public static string ReadUiResources(string path, int resourceType)
    {
        // Map resources only; never execute the input method or its DllMain.
        IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 0x22);
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), path);
        try
        {
            var text = new StringBuilder();
            Exception failure = null;
            ResourceNameCallback names = delegate(IntPtr library, IntPtr type, IntPtr name, IntPtr parameter)
            {
                ResourceLanguageCallback languages = delegate(IntPtr image, IntPtr kind, IntPtr id, ushort language, IntPtr ignored)
                {
                    IntPtr info = FindResourceEx(image, kind, id, language);
                    IntPtr memory = LoadResource(image, info);
                    IntPtr pointer = LockResource(memory);
                    uint size = SizeofResource(image, info);
                    if (info == IntPtr.Zero || memory == IntPtr.Zero || pointer == IntPtr.Zero || size == 0)
                    {
                        failure = new Win32Exception(Marshal.GetLastWin32Error(), path);
                        return false;
                    }
                    var bytes = new byte[size];
                    Marshal.Copy(pointer, bytes, 0, bytes.Length);
                    text.Append(Encoding.Unicode.GetString(bytes));
                    return true;
                };
                if (!EnumResourceLanguages(library, type, name, languages, IntPtr.Zero))
                {
                    if (failure == null) failure = new Win32Exception(Marshal.GetLastWin32Error(), path);
                    return false;
                }
                return true;
            };
            if (!EnumResourceNames(module, new IntPtr(resourceType), names, IntPtr.Zero))
            {
                int error = Marshal.GetLastWin32Error();
                if (failure != null) throw failure;
                if (error != 1813) throw new Win32Exception(error, path);
            }
            return text.ToString();
        }
        finally { FreeLibrary(module); }
    }
}
