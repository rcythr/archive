// Written in the D programming language.
/**
Functions and types that implement the TarPolicy used with the Archive template.

Copyright: Copyright Richard W Laughlin Jr. 2014—2016

License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors: Richard W Laughlin Jr.

Source: http://github.com/rcythr/archive

Policy for the Archive template which provides reading and writing of Tar files.

Reading Usage:
---
import archive.tar;
import std.stdio;

auto archive = new TarArchive(std.file.read("my.tar");

foreach(file; archive.files)
{
    writeln("Filename: ", file.path);
    writeln("Data: ", file.data);
}

---

Writing Usage:
---
import archive.tar;

auto archive = new TarArchive();

auto file = new TarArchive.File("languages/awesome.txt");
file.data = "D\n"; // can also set to immutable(ubyte)[]
archive.addFile(file);

std.file.write("lang.tar", cast(ubyte[])archive.serialize());

---

*/

module archive.tar;
import archive.core;

private import std.algorithm;
private import std.array;
private import std.container;
private import std.conv;
private import std.exception;
private import std.format;
private import std.string;

/**
 * Thrown when a tar file is not readable or contains errors.
 */
public class TarException : Exception
{
    this(string msg)
    {
        super("TarException: " ~ msg);
    }
}

/**
 * Helper struct for unix permissions
 */
public struct TarPermissions
{
    static immutable(uint) DIRECTORY = octal!40000;
    static immutable(uint) FILE = octal!100000;

    static immutable(uint) EXEC_SET_UID = octal!4000;
    static immutable(uint) EXEC_SET_GID = octal!2000;
    static immutable(uint) SAVE_TEXT = octal!1000;

    static immutable(uint) R_OWNER = octal!400;
    static immutable(uint) W_OWNER = octal!200;
    static immutable(uint) X_OWNER = octal!100;

    static immutable(uint) R_GROUP = octal!40;
    static immutable(uint) W_GROUP = octal!20;
    static immutable(uint) X_GROUP = octal!10;

    static immutable(uint) R_OTHER = octal!4;
    static immutable(uint) W_OTHER = octal!2;
    static immutable(uint) X_OTHER = octal!1;

    static immutable(uint) ALL = std.conv.octal!777;
}

/**
 * Enum class for types supported by tar files.
 *   Directory is given special treatment, all others
 *   have any content placed in the data field.
 */
public enum TarTypeFlag : char
{
    file = '0',
    altFile = '\0',
    hardLink = '1',
    symbolicLink = '2',
    characterSpecial = '3',
    blockSpecial = '4',
    directory = '5',
    fifo = '6',
    contiguousFile = '7',
}

/**
 * Policy class for reading and writing tar archives.
 * Features:
 *      + Handles files and directories of arbitrary size
 *      + Files and directories may have permissions
 *      + Files and directories may optionally set an owner and group name/id.
 * Limitations:
 *      + File paths may not exceed 255 characters - this is due to the format specification.
 */
public class TarPolicy
{
    static immutable(bool) isReadOnly = false;
    static immutable(bool) hasProperties = false;

    private static string trunc(string input)
    {
        for(size_t i=0; i < input.length; ++i)
        {
            if(input[i] == '\0')
            {
                return input[0 .. i];
            }
        }
        return input;
    }

    private static string intToOctalStr(uint value)
    {
        auto writer = appender!(string)();
        formattedWrite(writer, "%o ", value);
        return writer.data;
    }

    private static string longToOctalStr(ulong value)
    {
        auto writer = appender!(string)();
        formattedWrite(writer, "%o ", value);
        return writer.data;
    }

    private static uint octalStrToInt(char[] octal)
    {
        string s = cast(string)(std.string.strip(octal));
        int result = 0;
        formattedRead(s, "%o ", &result);
        return result;
    }

    private static ulong octalStrToLong(char[] octal)
    {
        string s = cast(string)(std.string.strip(octal));
        int result = 0;
        formattedRead(s, "%o ", &result);
        return result;
    }

    private static char[] strToBytes(string str, uint length)
    {
        char[] result = new char[length];
        result[0 .. min(str.length, length)] = str;
        result[str.length .. $] = 0;
        return result;
    }

    private static T[] nullArray(T)(uint length)
    {
        T[] result = new T[length];
        result[0 .. $] = 0;
        return result;
    }

    private struct TarHeader
    {
        private static uint unsignedSum(char[] values)
        {
            uint result = 0;
            foreach(char c ; values)
            {
                result += c;
            }
            return result;
        }

        private static uint signedSum(char[] values)
        {
            uint result = 0;
            foreach(byte b ; cast(byte[])values)
            {
                result += b;
            }
            return result;
        }

        char[100] filename;
        char[8] mode;
        char[8] ownerId;
        char[8] groupId;
        char[12] size;
        char[12] modificationTime;
        char[8] checksum;
        char linkId;
        char[100] linkedFilename;

        char[6] magic;
        char[2] tarVersion;
        char[32] owner;
        char[32] group;
        char[8] deviceMajorNumber;
        char[8] deviceMinorNumber;
        char[155] prefix;
        char[12] padding;

        bool confirmChecksum()
        {
            uint apparentChecksum = octalStrToInt(checksum);
            uint currentSum = calculateUnsignedChecksum();

            if(apparentChecksum != currentSum)
            {
                // Handle old tars which use a broken implementation that calculated the
                // checksum incorrectly (using signed chars instead of unsigned).
                currentSum = calculateSignedChecksum();
                if(apparentChecksum != currentSum)
                {
                    return false;
                }
            }
            return true;
        }

        void nullify()
        {
            filename = 0;
            mode = 0;
            ownerId = 0;
            groupId = 0;
            size = 0;
            modificationTime = 0;
            checksum = 0;
            linkId = 0;
            magic = 0;
            tarVersion = 0;
            owner = 0;
            group = 0;
            deviceMajorNumber = 0;
            deviceMinorNumber = 0;
            prefix = 0;
            padding = 0;
        }

        uint calculateUnsignedChecksum()
        {
            uint sum = 0;
            sum += unsignedSum(filename);
            sum += unsignedSum(mode);
            sum += unsignedSum(ownerId);
            sum += unsignedSum(groupId);
            sum += unsignedSum(size);
            sum += unsignedSum(modificationTime);
            sum += 32 * 8; // checksum is treated as all blanks
            sum += linkId;
            sum += unsignedSum(linkedFilename);
            sum += unsignedSum(magic);
            sum += unsignedSum(tarVersion);
            sum += unsignedSum(owner);
            sum += unsignedSum(group);
            sum += unsignedSum(deviceMajorNumber);
            sum += unsignedSum(deviceMinorNumber);
            sum += unsignedSum(prefix);
            return sum;
        }

        uint calculateSignedChecksum()
        {
            uint sum = 0;
            sum += signedSum(filename);
            sum += signedSum(mode);
            sum += signedSum(ownerId);
            sum += signedSum(groupId);
            sum += signedSum(size);
            sum += signedSum(modificationTime);
            sum += 32 * 8; // checksum is treated as all blanks
            sum += linkId;
            sum += signedSum(linkedFilename);
            sum += signedSum(magic);
            sum += signedSum(tarVersion);
            sum += signedSum(owner);
            sum += signedSum(group);
            sum += signedSum(deviceMajorNumber);
            sum += signedSum(deviceMinorNumber);
            sum += signedSum(prefix);
            return sum;
        }
    }

    private static ubyte[] POSIX_MAGIC_NUM = cast(ubyte[])"ustar\0";

    /**
     * Class for directories
     */
    public static class DirectoryImpl : ArchiveDirectory!(TarPolicy)
    {
        this() { super(""); }
        this(string path) { super(path); }
        this(string[] path) { super(path); }

        public uint permissions = TarPermissions.DIRECTORY | TarPermissions.ALL;
        public ulong modificationTime;

        // Posix Extended Fields
        public string owner = "";
        public string group = "";
    }

    /**
     * Class for files
     */
    public static class FileImpl : ArchiveMember
    {
        public this() { super(false, ""); }
        public this(string path) { super(false, path); }
        public this(string[] path) { super(false, path); }

        public uint permissions = TarPermissions.FILE | TarPermissions.ALL;
        public ulong modificationTime;
        public TarTypeFlag typeFlag = TarTypeFlag.file;
        public string linkName;

        @property immutable(ubyte)[] data()
        {
            return _data;
        }

        @property void data(immutable(ubyte)[] newdata)
        {
            _data = newdata;
        }

        @property void data(string newdata)
        {
            _data = cast(immutable(ubyte)[])newdata;
        }

        // Posix Extended Fields
        public string owner;
        public string group;

        private immutable(ubyte)[] _data = null;
    }

    /**
     * Deserialize method which loads data from a tar archive.
     */
    public static void deserialize(Filter)(void[] data, Archive!(TarPolicy,Filter) archive)
    {
        char numNullHeaders = 0;

        uint i = 0;

        // Loop through all headers
        while(numNullHeaders < 2 && i + 512 < data.length)
        {
            // Determine if null
            bool isNull = true;
            for(int j=0; j < 512; ++j)
            {
                if((cast(char[])data)[i + j] != '\0')
                {
                    isNull = false;
                    break;
                }
            }

            if(!isNull)
            {
                TarHeader* header = cast(TarHeader*)(&data[i]);
                i += 512;

                // Check the checksum
                if(!header.confirmChecksum())
                    throw new TarException("Invalid checksum");

                // Make sure we've dropped off any trailing nuls (strip doens't work because strip doesn't check for nuls!)
                string filename = trunc(cast(string)header.filename);
                string owner = "";
                string group = "";

                if(header.magic == "ustar\0")
                {
                    filename = trunc(cast(string)header.prefix) ~ filename;
                    owner = trunc(cast(string)header.owner);
                    group = trunc(cast(string)header.group);
                }

                // Insert the file into the file list
                if(cast(TarTypeFlag)(header.linkId) == TarTypeFlag.directory)
                {
                    DirectoryImpl dir = archive.addDirectory(filename);

                    dir.modificationTime = octalStrToLong(header.modificationTime);
                    // Add additional ustar properties (or "" if not present)
                    dir.owner = owner;
                    dir.group = group;
                }
                else
                {
                    FileImpl file = new FileImpl();
                    file.path = filename;
                    file.permissions = octalStrToInt(header.mode);
                    uint size = octalStrToInt(header.size);
                    file.modificationTime = octalStrToLong(header.modificationTime);
                    file.typeFlag = cast(TarTypeFlag)(header.linkId);

                    archive.addFile(file);

                    // Add additional ustar properties (or "" if not present)
                    file.owner = owner;
                    file.group = group;

                    if(file.typeFlag == TarTypeFlag.hardLink || file.typeFlag == TarTypeFlag.symbolicLink)
                    {
                        file.linkName = cast(string)(header.linkedFilename);
                    }

                    file._data = assumeUnique!(ubyte)(cast(ubyte[])data[i .. i + size]);
                    i += size;
                    if(size % 512 != 0)
                        i += (512 - (size % 512)); // Skip padding bytes in this chunk (if any)
                }
            }
            else
            {
                ++numNullHeaders;
                i += 512;
            }
        }
    }

    /**
     * Serialize method which writes data to a tar archive
     */
    public static void[] serialize(Filter)(Archive!(TarPolicy,Filter) archive)
    {
        ubyte[] serializeDirectory(DirectoryImpl dir, bool isRoot = false)
        {
            auto result = appender!(ubyte[])();
            TarHeader header;

            // Write out all files in the directory
            foreach(file; dir.files)
            {
                header.nullify();
                // Determine if we need the ustar extension
                string filename = file.path;
                string prefix = "";
                bool needUstar = false;

                // Compute the proper filename and prefix, if needed.
                // Throw an exception if a filepath exceeds 255 characters.
                if(file.path.length > 100)
                {
                    prefix = file.path[0 .. $-100];
                    filename = file.path[$-100 .. $];

                    // Check if we exceed the maximum filepath length for tar archives.
                    if(prefix.length > 155)
                    {
                        throw new TarException("Pths cannot exceed 255 characters in tar archives.");
                    }

                    header.prefix = strToBytes(prefix, 155);

                    needUstar = true;
                }


                // Write out file header
                header.filename = strToBytes(filename, 100);
                header.mode = (rightJustify(intToOctalStr(file.permissions), 7) ~ "\0");
                header.ownerId = rightJustify(intToOctalStr(0), 7) ~ "\0";
                header.groupId = rightJustify(intToOctalStr(0), 7) ~ "\0";
                header.size = rightJustify(intToOctalStr(cast(uint)file._data.length), 11) ~ " ";
                sformat(header.modificationTime, "%o", file.modificationTime);
                header.linkId = cast(char)(file.typeFlag);
                header.linkedFilename = strToBytes(file.linkName, 100);

                // Set owner name if needed.
                if(file.owner !is null && file.owner != "")
                {
                    header.owner = strToBytes(file.owner, 32);
                    needUstar = true;
                }

                // Set group name if needed
                if(file.group !is null && file.group != "")
                {
                    header.group = strToBytes(file.group, 32);
                    needUstar = true;
                }

                // Only set the ustar extensions if needed.
                if(needUstar)
                {
                    header.magic = strToBytes("ustar", 6);
                }

                // Compute checksum last.
                header.checksum = rightJustify(intToOctalStr(header.calculateUnsignedChecksum()), 7) ~ "\0";

                // Write out the header
                result.put((cast(ubyte*)(&header))[0 .. 512]);

                // Write out file data
                result.put(file._data[0 .. $]);

                // Write out padding
                if(file._data.length % 512 != 0)
                    result.put(nullArray!ubyte(512 - (file._data.length % 512)));
            }

            // Write out all directories in the directory
            foreach(directory; dir.directories)
            {
                header.nullify();

                string dirname = directory.path;
                bool needUstar = false;

                // Compute the proper filename and prefix, if needed.
                // Throw an exception if a filepath exceeds 255 characters.
                if(directory.path.length > 100)
                {
                    string prefix = directory.path[0 .. $-100];
                    dirname = directory.path[$-100 .. $];

                    // Check if we exceed the maximum filepath length for tar archives.
                    if(prefix.length > 155)
                    {
                        throw new TarException("Paths cannot exceed 255 characters in tar archives.");
                    }

                    header.prefix = strToBytes(prefix, 155);

                    needUstar = true;
                }

                header.filename = strToBytes(dirname, 100);
                header.mode = rightJustify(intToOctalStr(directory.permissions), 7) ~ "\0";
                header.ownerId = rightJustify(intToOctalStr(0), 7) ~ "\0";
                header.groupId = rightJustify(intToOctalStr(0), 7) ~ "\0";
                header.size = rightJustify(intToOctalStr(0), 11) ~ " ";
                sformat(header.modificationTime, "%o", directory.modificationTime);
                header.linkId = cast(char)(TarTypeFlag.directory);

                // Set owner name if needed.
                if(directory.owner !is null && directory.owner != "")
                {
                    header.owner = strToBytes(directory.owner, 32);
                    needUstar = true;
                }

                // Set group name if needed
                if(directory.group !is null && directory.group != "")
                {
                    header.group = strToBytes(directory.group, 32);
                    needUstar = true;
                }

                // Only set the ustar extensions if needed.
                if(needUstar)
                {
                    header.magic = strToBytes("ustar", 6);
                }

                // Compute checksum last.
                header.checksum = rightJustify(intToOctalStr(header.calculateUnsignedChecksum()), 7) ~ "\0";

                // Write out the header
                result.put((cast(ubyte*)(&header))[0 .. 512]);

                // Recurse into this directory and write out sub-directories and sub-files.
                result.put(serializeDirectory(directory));
            }

            return result.data;
        }

        auto finalResult = appender!(ubyte[])();
        finalResult.put(serializeDirectory(archive.root, true));
        finalResult.put(nullArray!ubyte(1024));

        return finalResult.data;
    }
};

/**
 * Convenience alias that simplifies the interface for users
 */
alias TarArchive = Archive!(TarPolicy);

unittest
{
    immutable February2023 = 1675_341_079;
    string data1 = "HELLO\nI AM A FILE WITH SOME DATA\n1234567890\nABCDEFGHIJKLMOP";
    immutable(ubyte)[] data2 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    TarArchive output = new TarArchive();

    // Add file into the top level directory.
    TarArchive.File file1 = new TarArchive.File();
    file1.path = "apple.txt";
    file1.data = data1;
    file1.modificationTime = February2023;
    output.addFile(file1);

    // Add a file into a non top level directory.
    TarArchive.File file2 = new TarArchive.File("directory/directory/directory/apple.txt");
    file2.data = data2;
    file2.modificationTime = February2023 + 42;
    output.addFile(file2);

    // Add a directory that already exists.
    output.addDirectory("directory/");

    // Add a directory that does not exist.
    output.addDirectory("newdirectory/");

    // Remove unused directories
    output.removeEmptyDirectories();

    // Make sure we have non-0 modification time on at least one directory
    output.getDirectory("directory/").modificationTime = February2023 + 84;

    // Ensure the only unused directory was removed.
    assert(output.getDirectory("newdirectory") is null);

    // Re-add a directory that does not exist so we can test its output later.
    output.addDirectory("newdirectory/");

    // Serialize the zip archive and construct a new zip with it
    TarArchive input = new TarArchive(output.serialize());

    // Make sure that there is a file named apple.txt and a file named directory/directory/directory/apple.txt
    if (auto file = input.getFile("apple.txt"))
        assert(file.modificationTime == February2023);
    else
        assert(0, "Required file is not present after deserialization");
    assert(input.getFile("directory/directory/directory/apple.txt") !is null);

    if (auto dir = input.getDirectory("directory/"))
        assert(dir.modificationTime == February2023 + 84);
    else
        assert(0, "Required directory is not present after deserialization");

    // Make sure there are no extra directories or files
    assert(input.numFiles() == 2);
    assert(input.numDirectories() == 4);
    assert(input.numMembers() == 6);
}
