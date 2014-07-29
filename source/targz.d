/**
Type that implements the TarGz Filter used with the Archive template.

Copyright: Copyright Richard W Laughlin Jr. 2014

License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors: Richard W Laughlin Jr.

Source: http://github.com/rcythr/archive 
*/

module archive.targz;

import archive.core;
import archive.tar;

private import etc.c.zlib;
private import std.algorithm;
private import std.array;
private import std.zlib;

/**
 * Filter class which can be used by the Archive class to compress/decompress
 *   files into a .gz format.
 */
public class GzFilter
{
    /**
     * Input data is wrapped with gzip and returned.
     */
    public static void[] compress(void[] data)
    {
        auto result = appender!(ubyte[])();
        
        Compress compressor = new Compress(HeaderFormat.gzip);
        for(uint i=0; i < data.length; i += 1024)
        {
            result.put(cast(ubyte[])compressor.compress(data[i .. min(i+1024, data.length)]));
        }
        result.put(cast(ubyte[])compressor.flush());
        
        return result.data;
    }
    
    /**
     * Input data is processed to extract from the gzip format.
     */
    public static void[] decompress(void[] data)
    {
        auto result = appender!(ubyte[])();
        
        UnCompress uncompressor = new UnCompress();
        for(uint i=0; i < data.length; i += 1024)
        {
            result.put(cast(ubyte[])uncompressor.uncompress(data[i .. min(i+1024, data.length)]));
        }
        result.put(cast(ubyte[])uncompressor.flush());
        
        return result.data;
    }
}

/**
 * Convenience alias that simplifies the interface for users
 */
alias TarGzArchive = Archive!(TarPolicy, GzFilter); 

unittest
{
    string data1 = "HELLO\nI AM A FILE WITH SOME DATA\n1234567890\nABCDEFGHIJKLMOP";
    immutable(ubyte)[] data2 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    TarGzArchive output = new TarGzArchive();

    // Add file into the top level directory.
    TarGzArchive.File file1 = new TarGzArchive.File();
    file1.path = "apple.txt";
    file1.data = data1;
    output.addFile(file1);

    // Add a file into a non top level directory.
    TarGzArchive.File file2 = new TarGzArchive.File("directory/directory/directory/apple.txt");
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
    TarGzArchive input = new TarGzArchive(output.serialize());

    // Make sure that there is a file named apple.txt and a file named directory/directory/directory/apple.txt
    assert(input.getFile("apple.txt") !is null);
    assert(input.getFile("directory/directory/directory/apple.txt") !is null);

    // Make sure there are no extra directories or files
    assert(input.numFiles() == 2);
    assert(input.numDirectories() == 4);
    assert(input.numMembers() == 6);
}
