/**
Functions and Types that implement the Zip Policy used with the Archive template.

Copyright: Copyright Richard W Laughlin Jr. 2014—2016

License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors: Refactored into Policy by Richard W Laughlin Jr.
         Original zip code by $(WEB digitalmars.com, Walter Bright)

Source: http://github.com/rcythr/archive

Policy for the Archive template which provides reading and writing of Zip files.

Reading Usage:
---
import archive.zip;
import std.stdio;

auto archive = new ZipArchive(std.file.read("my.zip");

foreach(file; archive.files)
{
    writeln("Filename: ", file.path);
    writeln("Data: ", file.data);
}

---

Writing Usage:
---
import archive.zip;

auto archive = new ZipArchive();

auto file = new ZipArchive.File("languages/awesome.txt");
file.data = "D\n"; // can also set to immutable(ubyte)[]
archive.addFile(file);

std.file.write("lang.zip", cast(ubyte[])archive.serialize());

---

*/

module archive.zip;
import archive.core;

private import std.algorithm;
private import std.array;
private import std.bitmanip : littleEndianToNative, nativeToLittleEndian;
private import core.bitop;
private import std.container;
private import std.conv;
private import std.datetime;
private import std.exception;
private import std.string;
private import std.zlib;

/**
 * Thrown when a zip file is not readable or contains errors.
 */
public class ZipException : Exception
{
    this(string msg)
    {
        super("ZipException: " ~ msg);
    }
}

/**
 * Specifies the compression for a particular zip entry.
 */
public enum CompressionMethod : ushort
{
    none = 0,
    deflate = 8,
}

/**
 * Policy class for reading and writing zip archives.
 *
 * Currently lacks support for:
 *      + Multiple disk zip files
 *      + Compression algorithms other than deflate
 *      + Zip64
 *      + Encryption
 */
public class ZipPolicy
{
    static immutable(bool) isReadOnly = false;
    static immutable(bool) hasProperties = true;

    private static immutable(ubyte[]) DIRECTORY_MAGIC_NUM = cast(immutable(ubyte[]))"PK\x01\x02";
    private static immutable(ubyte[]) RECORD_MAGIC_NUM = cast(immutable(ubyte[]))"PK\x03\x04";
    private static immutable(ubyte[]) END_DIRECTORY_MAGIC_NUM = cast(immutable(ubyte[]))"PK\x05\x06";

    /**
     * Directory implementation for Zip archives. Provides any additional functionality required by ZipArchives.
     */
    public static class DirectoryImpl : ArchiveDirectory!(ZipPolicy)
    {
        public this() { }
        public this(string path) { super(path); }
        public this(string[] path) { super(path); }
    }

    /**
     * File implementation for Zip archives. Provides any additional functionality required of files by ZipArchives.
     */
    public static class FileImpl : ArchiveMember
    {
        public this() { super(false); }
        public this(string path) { super(false, path); }
        public this(string[] path) { super(false, path); }

        /*
         * Compresses the uncompressed data in this file (if needed).
         */
        private void decompress()
        {
            if(_decompressedData == null)
            {
                switch (_compressionMethod)
                {
                    case CompressionMethod.none:
                        _decompressedData = _compressedData;
                        break;
                    case CompressionMethod.deflate:
                        // -15 is a magic value used to decompress zip files.
                        // It has the effect of not requiring the 2 byte header
                        // and 4 byte trailer.
                        _decompressedData = assumeUnique!(ubyte)(cast(ubyte[])std.zlib.uncompress(cast(void[])_compressedData, _decompressedSize, -15));
                        break;
                    default:
                        throw new ZipException("unsupported compression method");
                }
            }
        }

        /*
         * Decompresses the compressed data in this file (if needed).
         */
        private void compress()
        {
            if(_compressedData == null)
            {
                switch (_compressionMethod)
                {
                    case CompressionMethod.none:
                        _decompressedData = _compressedData;
                        break;
                    case CompressionMethod.deflate:
                        // -15 is a magic value used to decompress zip files.
                        // It has the effect of not requiring the 2 byte header
                        // and 4 byte trailer.
                        _compressedData = assumeUnique!(ubyte)(cast(ubyte[])std.zlib.compress(cast(void[])_decompressedData));
                        _compressedData = _compressedData[2 .. _compressedData.length - 4];
                        break;
                    default:
                        throw new ZipException("unsupported compression method");
                }
            }
        }

        /**
         * Returns: the decompressed data.
         */
        @property public immutable(ubyte)[] data()
        {
            decompress();
            return _decompressedData;
        }

        /**
         * Sets the decompressed data.
         */
        @property public void data(immutable(ubyte)[] data)
        {
            _decompressedData = data;
            _decompressedSize = cast(uint)data.length;
            _compressedData = null;

            // Recalculate CRC
            _crc32 = std.zlib.crc32(0, cast(void[])_decompressedData);
        }

        /** ditto */
        @property public void data(string newdata)
        {
            data(cast(immutable(ubyte)[])newdata);
        }

        /**
         * Returns: the compressed data
         */
        @property public immutable(ubyte)[] compressed()
        {
            compress();
            return _compressedData;
        }

        /**
         * Returns: the compression method.
         */
        @property public CompressionMethod compressionMethod() { return _compressionMethod; }

        /**
         * Sets the compression method that will be used.
         */
        @property public void compressionMethod(CompressionMethod method)
        {
            if(method != _compressionMethod)
            {
                // First make sure the data is already extracted (if needed)
                decompress();

                // Clean out stale compressed data
                _compressionMethod = method;
                _compressedData = null;
            }
        }

        /**
         * Additional data stored within the zip archive for this file.
         */
        public ubyte[] extra;

        /**
         * The comment for the member of the archive.
         */
        public string comment = "";

        /**
         * The time when the file was last modified.
         */
        public DosFileTime modificationTime;

        /**
         * Zip related flags specific for this member, as specified by the Zip format documentation.
         */
        public ushort flags;

        /**
         * The internal attributes specific to this member, as specified by the Zip format documentation.
         */
        public ushort internalAttributes;

        /**
         * The internal attributes specific to this member, as specified by the Zip format documentation.
         */
        public uint externalAttributes;

        private immutable(ubyte)[] _compressedData = null;
        private immutable(ubyte)[] _decompressedData = null;
        private uint _compressedSize;
        private uint _decompressedSize;
        private uint _crc32;
        private uint _offset;
        private CompressionMethod _compressionMethod = CompressionMethod.deflate;
    }

    /**
     * Archive-wide properties for ZipArchives.
     */
    public static class Properties
    {
        /**
         * Archive-wide File comment stored in the archive.
         */
        public string comment;
    }

    /*
     * Fetches the local header data for a file in the archive - most importantly the stored data
     */
    private static void expandMember(void[] data, FileImpl file, int offset)
    {
        ushort getUShort()
        {
            ubyte[2] result = cast(ubyte[])data[offset .. offset+2];
            offset += 2;
            return littleEndianToNative!ushort(result);
        }

        uint getUInt()
        {
            ubyte[4] result = cast(ubyte[])data[offset .. offset+4];
            offset += 4;
            return littleEndianToNative!uint(result);
        }

        if(data[offset .. offset + 4] != RECORD_MAGIC_NUM)
            throw new ZipException("Invalid directory entry 4");
        offset += 4;

        ushort minExtractVersion = getUShort();
        file.flags = getUShort();
        file._compressionMethod = cast(CompressionMethod)getUShort();
        file.modificationTime = cast(DosFileTime)getUInt();
        file._crc32 = getUInt();
        uint compressedSize = max(file._compressedSize, getUInt());
        file._decompressedSize = max(file._decompressedSize, getUInt());
        ushort namelen = getUShort();
        ushort extralen = getUShort();

        int dataOffset = offset + namelen + extralen;
        file._compressedData = assumeUnique!(ubyte)(cast(ubyte[])data[dataOffset .. dataOffset + compressedSize]);
    }

    /**
     * Deserialize method which loads data from a zip archive and stores it in archive.
     */
    public static void deserialize(Filter)(void[] data, Archive!(ZipPolicy, Filter) archive)
    {
        int iend, i;
        int endrecoffset;

        // Helper functions
        ushort getUShort()
        {
            ubyte[2] result = cast(ubyte[])data[i .. i+2];
            i += 2;
            return littleEndianToNative!ushort(result);
        }

        uint getUInt()
        {
            ubyte[4] result = cast(ubyte[])data[i .. i+4];
            i += 4;
            return littleEndianToNative!uint(result);
        }

        // Calculate the ending record
        iend = to!uint(data.length) - 66000;
        if(iend < 0)
            iend = 0;

        for(i = to!uint(data.length) - 22; 1; --i)
        {
            if( i < iend )
                throw new ZipException("No end record.");

            if(data[i .. i+4] == END_DIRECTORY_MAGIC_NUM)
            {
                i += 20;
                ushort endcommentlength = getUShort();
                if (i + endcommentlength > data.length)
                {
                    i -= 22;
                    continue;
                }

                archive.properties.comment = cast(string)(data[i .. i + endcommentlength]);
                endrecoffset = i - 22;
                break;
            }
        }
        i -= 18;

        ushort diskNumber = getUShort();
        ushort diskStartDir = getUShort();
        ushort numEntries = getUShort();
        ushort totalEntries = getUShort();

        if(numEntries != totalEntries)
            throw new ZipException("Multiple disk zips not supported");

        uint directorySize = getUInt();
        uint directoryOffset = getUInt();

        if(directoryOffset + directorySize > endrecoffset)
            throw new ZipException("Corrupted Directory");

        i = directoryOffset;
        for(int n = 0; n < numEntries; ++n)
        {
            if(data[i .. i + 4] != DIRECTORY_MAGIC_NUM)
                throw new ZipException("Invalid directory entry 1");

            i += 4;

            FileImpl file = new FileImpl();
            ushort madeVersion = getUShort();
            ushort minExtractVersion = getUShort();
            file.flags = getUShort();
            file._compressionMethod = cast(CompressionMethod)getUShort();
            file.modificationTime = cast(DosFileTime)getUInt();
            file._crc32 = getUInt();
            file._compressedSize = getUInt();
            file._decompressedSize = getUInt();
            ushort nameLen = getUShort();
            ushort extraLen = getUShort();
            ushort commentLen = getUShort();
            ushort memberDiskNumber = getUShort();
            file.internalAttributes = getUShort();
            file.externalAttributes = getUInt();
            uint offset = getUInt();

            if(i + nameLen + extraLen + commentLen > directoryOffset + directorySize)
                throw new ZipException("Invalid Directory Entry 2");

            file.path = cast(string)(data[i .. i + nameLen]);
            i += nameLen;

            file.extra = cast(ubyte[])data[i .. i + extraLen];
            i += extraLen;

            file.comment = cast(string)(data[i .. i + commentLen]);
            i += commentLen;

            // Expand the actual file to get the compressed data now.
            expandMember(data, file, offset);

            // Add the Member to the Listing
            if(file.path.endsWith("/"))
            {
                archive.addDirectory(file.path);
            }
            else
            {
                archive.addFile(file);
            }
        }
        if( i != directoryOffset + directorySize)
            throw new ZipException("Invalid directory entry 3");
    }

    /**
     * Serialize method which writes data stored in the archive to an array and returns it.
     */
    public static void[] serialize(Filter)(Archive!(ZipPolicy, Filter) archive)
    {
        if(archive.properties.comment.length > 0xFFFF)
            throw new ZipException("Archive comment longer than 655535");

        // Ensure each file is compressed; compute size
        uint archiveSize = 0;
        uint directorySize = 0;
        foreach(file; archive.files)
        {
            file.compress();
            archiveSize += 30 + file.path.length + file.extra.length + file._compressedData.length;
            directorySize += 46 + file.path.length + file.extra.length + file.comment.length;
        }

        ubyte[] data = new ubyte[archiveSize + directorySize + 22 + archive.properties.comment.length];

        // Helper Functions
        uint i = 0;
        void putUShort(ushort us)
        {
            data[i .. i + 2] = nativeToLittleEndian(us);
            i += 2;
        }

        void putUInt(uint ui)
        {
            data[i .. i + 4] = nativeToLittleEndian(ui);
            i += 4;
        }

        // Store Records
        foreach(file ; archive.files)
        {
            file._offset = i;
            data[i .. i + 4] = RECORD_MAGIC_NUM;
            i += 4;

            putUShort(20); // Member Minimum Extract Version
            putUShort(file.flags);
            putUShort(file.compressionMethod);
            putUInt(cast(uint)file.modificationTime);
            putUInt(file._crc32);
            putUInt(cast(uint)file._compressedData.length);
            putUInt(cast(uint)file._decompressedData.length);
            putUShort(cast(ushort)file.path.length);
            putUShort(cast(ushort)file.extra.length);

            data[i .. i + file.path.length] = (cast(ubyte[])file.path)[];
            i += file.path.length;

            data[i .. i + file.extra.length] = (cast(ubyte[])file.extra)[];
            i += file.extra.length;

            data[i .. i + file._compressedData.length] = file.compressed[];
            i += file._compressedData.length;
        }

        // Store Directory Entries
        uint directoryOffset = i;
        ushort numEntries = 0;
        foreach(file ; archive.files)
        {
            data[i .. i+4] = DIRECTORY_MAGIC_NUM;
            i += 4;

            putUShort(20); // Made Version
            putUShort(20); // Min Extract Version
            putUShort(file.flags);
            putUShort(cast(ushort)file.compressionMethod);
            putUInt(cast(uint)file.modificationTime);
            putUInt(file._crc32);
            putUInt(cast(uint)file._compressedData.length);
            putUInt(cast(uint)file._decompressedSize);
            putUShort(cast(ushort)file.path.length);
            putUShort(cast(ushort)file.extra.length);
            putUShort(cast(ushort)file.comment.length);
            putUShort(0); // Disk Number
            putUShort(file.internalAttributes);
            putUInt(file.externalAttributes);
            putUInt(file._offset);

            data[i .. i + file.path.length] = (cast(ubyte[])file.path)[];
            i += file.path.length;

            data[i .. i + file.extra.length] = (cast(ubyte[])file.extra)[];
            i += file.extra.length;

            data[i .. i + file.comment.length] = (cast(ubyte[])file.comment)[];
            i += file.comment.length;

            ++numEntries;
        }

        // Write End Directory Entry
        data[i .. i+4] = END_DIRECTORY_MAGIC_NUM;
        i += 4;

        putUShort(0); // Disk Number
        putUShort(0); // Disk Start Dir
        putUShort(numEntries); // Number of Entries
        putUShort(numEntries); // Total Number of Entries
        putUInt(directorySize);
        putUInt(directoryOffset);
        putUShort(cast(ushort)archive.properties.comment.length);

        data[i .. data.length] = (cast(ubyte[])archive.properties.comment)[];

        // Return result
        return cast(void[])data;
    }
};

/**
 * Convenience alias that simplifies the interface for users
 */
alias ZipArchive = Archive!ZipPolicy;

unittest
{
    string data1 = "HELLO\nI AM A FILE WITH SOME DATA\n1234567890\nABCDEFGHIJKLMOP";
    immutable(ubyte)[] data2 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    ZipArchive output = new ZipArchive();

    // Add file into the top level directory.
    ZipArchive.File file1 = new ZipArchive.File();
    file1.path = "apple.txt";
    file1.data = data1;
    output.addFile(file1);

    // Add a file into a non top level directory.
    ZipArchive.File file2 = new ZipArchive.File("directory/directory/directory/apple.txt");
    file2.data = data2;
    output.addFile(file2);

    // Add a directory that already exists.
    output.addDirectory("directory/");

    // Add a directory that does not exist.
    output.addDirectory("newdirectory/");

    // Remove unused directories
    output.removeEmptyDirectories();

    // Ensure the only unused directory was removed.
    assert(output.getDirectory("newdirectory") is null);

    // Re-add a directory that does not exist so we can test its output later.
    output.addDirectory("newdirectory/");

    // Serialize the zip archive and construct a new zip with it
    ZipArchive input = new ZipArchive(output.serialize());

    // Make sure that there is a file named apple.txt and a file named directory/directory/directory/apple.txt
    assert(input.getFile("apple.txt") !is null);
    assert(input.getFile("directory/directory/directory/apple.txt") !is null);

    // Make sure there are no extra directories or files
    assert(input.numFiles() == 2);
    assert(input.numDirectories() == 3);
    assert(input.numMembers() == 5);
}
