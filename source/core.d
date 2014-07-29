// Written in the D programming language.
/**
Types that handle the core logic of archive file formats.

Copyright: Copyright Richard W Laughlin Jr. 2014

License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors: Richard W Laughlin Jr.

Source: http://github.com/rcythr/archive

*/

module archive.core;

private import std.container;
private import std.string;

public class IllegalPathException : Exception
{
    this(string msg) { super("IllegalPathException: " ~ msg); }
}

/**
 * The basic filter which is used for archives which do not have wrapper-based compression.
 */
public class NullArchiveFilter
{
    public static void[] compress(void[] data) { return data; }
    public static void[] decompress(void[] data) { return data; }
}

/**
 * A class which is extended by the FileImpl and DirectoryImpl classes of the
 *   policy classes.
 */
public class ArchiveMember
{
    private bool _isDirectory;
    protected string _path;

    this(bool isDirectory)
    {
        _isDirectory = isDirectory;
        _path = "";
    }

    this(bool isDirectory, string mypath)
    {
        _isDirectory = isDirectory;
        _path = mypath;
    }

    this(bool isDirectory, string[] pathParts)
    {
        _isDirectory = isDirectory;
        _path = join(pathParts, "/");
    }

    /**
     * Returns true iff this member is a directory member.
     */
    @property bool isDirectory() { return _isDirectory; }

    /**
     * Returns true iff this member is a non-directory (usually a file).
     */
    @property bool isFile() { return !_isDirectory; }

    /**
     * Returns the last entry in this member's path. (e.g for the path "myDir/dmd" this method returns dmd)
     */
    @property public string name() 
    { 
        string[] parts = split(_path, '/'); 
        return parts[$-1]; 
    }

    /**
     * Sets the last entry in this member's path. (e.g. for the path "myDir/dmd" a call with "rdmd" would result
     *    in a path of "myDir/rdmd".
     * 
     * Shall not be empty. Remove the member instead.
     * Shall not end in a '/' if this member is a file.
     *
     * Remove this member from any containing archives before calling this method.
     */
    @property public void name(string newname)
    { 
        string[] parts = split(_path, '/'); 
        parts[$-1] = newname; 
        _path = join(parts, "/"); 
    }

    /**
     * Returns the path of this member.
     */
    @property string path() 
    { 
        return _path; 
    }

    /**
     * Sets the full path of this member. Should not begin with "/". Should end in "/" iff this member is
     *   a directory. Should not be empty.
     */
    @property void path(string newpath)
    { 
            _path = newpath; 
    }
}

/**
 * Subclass of the ArchiveMember class which adds common functionality to all policy directory classes.
 */
public class ArchiveDirectory(Policy) : ArchiveMember
{
    /**
     * Public aliases to simplify both user and archive code.
     */
    public alias File = Policy.FileImpl;
    public alias Directory = Policy.DirectoryImpl;
    
    /**
     * Default constructor for unnamed directories (i.e. root)
     */
    public this() { super(true, ""); }
   
    /**
     * Constructors for named directories.
     */ 
    public this(string mypath) { super(true, mypath); }
    public this(string[] parts) { super(true, parts); }
    
    /**
     * Adds a member to the archive, creating subdirectories as necessary.
     */
    public void addFile(string[] pathParts, File file, uint i=0)
    {
        if(i == pathParts.length-1)
        {
            // Check that a directory of the same name does not exist
            if(pathParts[i] in directories)
            {
                throw new IllegalPathException("Cannot add file due to existing directory by the same name: " ~ join(pathParts, "/"));
            }

            // Add the member to this node.
            files[pathParts[i]] = file;
        }
        else
        {
            Directory* dir = pathParts[i] in directories;
            if(!dir)
            {
                // Check that a file of the same name does not exist.
                if(pathParts[i] in files)
                {
                    throw new IllegalPathException("Cannot add directory due to existing file by the same name: " ~ join(pathParts[0 .. i+1], "/"));
                }

                // Construct the Directory
                Directory directory = new Directory(pathParts[0 .. i+1]);
                directories[pathParts[i]] = directory;
                dir = &directory;
            }
            dir.addFile(pathParts, file, i+1);
        }
    }
    
    /**
     * Adds a chain of subdirectories, creating them as necessary.
     */
    public Directory addDirectory(string[] pathParts, uint i=0)
    {
        // Empty string handles case where root directory is added.
        // Some tar archivers will place it into the archive to store permissions/ownership
        Directory* dir = pathParts[i] in directories;
        if(!dir)
        {
            // Check that a file of the same name does not exist.
            if(pathParts[i] in files)
            {
                throw new IllegalPathException("Cannot add directory due to existing file by the same name: " ~ join(pathParts[0 .. i+1], "/"));
            }

            Directory directory = new Directory(pathParts[0 .. i+1]);
            directories[pathParts[i]] = directory;
            dir = &directory;
        }

        if(i == pathParts.length-1)
        {
            return *dir;
        }
        else
        {
            return dir.addDirectory(pathParts, i+1);
        }
    }
   
    /**
     * Attempts to remove a member from the archive.
     */
    public bool removeFile(string[] pathParts, uint i=0)
    {
        if(i == pathParts.length-1)
        {
            return files.remove(pathParts[i]);
        }
        else
        {
            Directory* dir = pathParts[i] in directories;
            if(dir)
            {
                return dir.removeFile(pathParts, i+1);
            }
        }
        return false;
    }

    /**
     * Attempts to remove a directory from the archive.
     */
    public bool removeDirectory(string[] pathParts, uint i=0)
    {
        if(i == pathParts.length-1)
        {
            return directories.remove(pathParts[i]);
        }
        else
        {
            Directory* dir = pathParts[i] in directories;
            if(dir)
            {
                return dir.removeDirectory(pathParts, i+1);
            }
        }
        return false;
    }
    
    /**
     * Removes all empty directories from the archive. 
     */
    public uint removeEmptyDirectories()
    {
        uint count = 0;

        SList!string toRemove;

        foreach(string key; directories.byKey)
        {
            uint subdirCount = directories[key].removeEmptyDirectories();
            if(subdirCount == 0)
            {
                toRemove.insertFront(key);
            }
            else
            {
                count += subdirCount;
            }
        }
        
        foreach(string key; toRemove)
        {
            directories.remove(key);
        }

        count += files.length;
        return count;
    }
   
    /**
     * Returns a file from the directory if it exists, otherwise null.
     */
    public File getFile(string[] pathParts, uint i=0)
    {
        if(i == pathParts.length-1)
        {
            File* file = pathParts[i] in files;
            return (file) ? *file : null;
        }
        else
        {
            Directory* dir = pathParts[i] in directories;
            if(!dir)
                return null;
            return dir.getFile(pathParts, i+1);
        }
    }
    
    /**
     * Returns the number of files up to n levels deep. Current directory is level 0.
     */
    public size_t numFiles(size_t n, size_t cur=0) 
    {
        if(n == cur)
        {
            return files.length;
        }
        else
        {
            size_t result = files.length; // All files in this directory.
            foreach(dir; directories.byValue)
            {
                result += dir.numFiles(n, cur+1);
            }
            return result;
        }
    }

    /**
     * Returns the number of directories up to n levels deep. Current directory is level 0.
     */
    public size_t numDirectories(size_t n, size_t cur=0) 
    { 
        if(n == cur)
        {
            return directories.length; // The number of directories in this directory + this directory.
        }
        else
        {
            size_t result = 0;
            foreach(dir; directories.byValue)
            {
                result += 1 + dir.numDirectories(n, cur+1);
            }
            return result;
        }
    }

    /**
     * Returns the number of files and directories up to n levels deep. Current directory is level 0.
     */
    public size_t numMembers(size_t n, size_t cur=0) 
    { 
        if(n == cur)
        {
            return files.length + directories.length; // All files/directories in this directory.
        }
        else
        {
            size_t result = files.length; // All the files in this directory.
            foreach(dir; directories.byValue)
            {
                result += 1 + dir.numMembers(n, cur+1); // A subdirectory and the files/directories inside it.
            }
            return result;
        }
    }

    /**
     * Returns a directory from this directory if it exists, otherwise null.
     */
    public Directory getDirectory(string[] pathParts, uint i=0)
    {
        Directory* dir = pathParts[i] in directories;
        if(!dir)
            return null;

        if(i == pathParts.length-1)
        {
            return *dir;
        }
        else
        {
            return dir.getDirectory(pathParts, i+1);
        }
    }

    /**
     * Convenience method for recursively iterating over files in this directory.
     */
    public int filesOpApply(int delegate(ref File) dg)
    {
        int result = 0;
        foreach(Directory ad; directories)
        {
            result = ad.filesOpApply(dg);
            if(result) 
                return result;
        }
        
        foreach(File am; files)
        {
            result = dg(am);
            if(result)
                return result;
        }
        return result;
    }
    
    /**
     * Convenience method for recursively iterating over directories in this directory.
     */
    public int directoriesOpApply(int delegate(ref Directory) dg)
    {
        int result = 0;
        foreach(Directory ad; directories)
        {
            result = dg(ad);
            if(result)
                return result;
            
            result = ad.directoriesOpApply(dg);
            if(result) 
                return result;
        }
        
        return result;
    }
    
    /**
     * Convenience method for recursively iterating over files and directories in this directory.
     */
    public int membersOpApply(int delegate(ref ArchiveMember) dg)
    {
        int result = 0;
        foreach(Directory ad; directories)
        {
            ArchiveMember entry = ad;
            
            result = dg(entry);
            if(result)
                return result;
            
            result = ad.membersOpApply(dg);
            if(result) 
                return result;
        }
        
        foreach(File am; files)
        {
            ArchiveMember entry = am;
            
            result = dg(entry);
            if(result)
                return result;
        }
        return result;
    }
    
    /**
     * Associative array of subdirectories.
     */
    public Directory[string] directories;
    
    /**
     * Associative array of files in this directly.
     */
    public File[string] files;
}

/**
*/
public class Archive(T, Filter = NullArchiveFilter)
{    
    /**
     * Convenience aliases which allow user code to refer to policy classes without being
     *   aware of the policies.
     */
    alias File = T.FileImpl;
    alias Directory = T.DirectoryImpl;
    
    static if(T.hasProperties)
    {
        alias Properties = T.Properties;
    }
    
    /**
     * Creates a new archive, initializing with the data serialized in the given array.
     */
    public this(void[] data) 
    {
        // Cannot call this() because it may not be defined.
        _root = new Directory(); 
        static if(T.hasProperties)
        {
            _properties = new Properties();
            T.deserialize(Filter.decompress(data), _root, _properties); 
        }
        else
        {
            T.deserialize(Filter.decompress(data), _root);
        }
    }
   
    static if(!T.isReadOnly)
    {
        /**
         * Creates a new archive.
         */
        public this() 
        { 
            _root = new Directory(); 
            static if(T.hasProperties)
                _properties = new Properties(); 
        }
    }

    /**
     * Returns the root directory of the archive.
     */
    @property ArchiveDirectory!T root() { return _root; }
    
    /**
     * Returns a delegate which will allow foreach iteration over files in the archive.
     */
    @property public int delegate(int delegate(ref File)) files() { return &_root.filesOpApply; }
    
    /**
     * Returns a delegate which will allow foreach iteration over directories in the archive.
     */
    @property public int delegate(int delegate(ref Directory)) directories() { return &_root.directoriesOpApply; }
    
    /**
     * Returns a delegate which will allow foreach iteration over files and directories in the archive.
     */
    @property public int delegate(int delegate(ref ArchiveMember)) members() { return &_root.membersOpApply; }

    /**
     * Returns a file from the archive if it exists, otherwise null.
     */
    public File getFile(string path) 
    { 
        return _root.getFile(split(path, "/")); 
    }

    /**
     * Returns a directory from the archive if it exists, otherwise null.
     */
    public Directory getDirectory(string path) 
    { 
        if(path.length == 0) // Handle ""
        {
            return _root;
        }
        else if(path[$-1] == '/') // Handle paths ending with /
        {
            return _root.getDirectory(split(path, "/")[0 .. $-1]);
        }
        else // Handle paths ending without /
        {
            return _root.getDirectory(split(path, "/")); 
        }
    }

    /**
     * Returns the number of files up to n levels deep. Root is level 0.
     */
    public size_t numFiles(size_t n=size_t.max) { return _root.numFiles(n); }

    /**
     * Returns the number of directories up to n levels deep. Root is level 0.
     */
    public size_t numDirectories(size_t n=size_t.max) { return _root.numDirectories(n); }

    /**
     * Returns the number of files and directories up to n levels deep. Root is level 0.
     */
    public size_t numMembers(size_t n=size_t.max) { return _root.numMembers(n); }

    static if(!T.isReadOnly)
    {
        /**
         * Serializes the current archive and returns the data array.
         */
        public void[] serialize() 
        { 
            static if(T.hasProperties)
            {
                return Filter.compress(T.serialize(_root, _properties)); 
            }
            else
            {
                return Filter.compress(T.serialize(_root));
            }
        }
    
        /**
         * Adds a member to the archive, adding intermediate directories as needed.
         */
        public void addFile(File member) { _root.addFile(split(member.path, "/"), member); }
        
        /**
         * Adds a directory to the archive, adding intermediate directories as needed.
         */
        public void addDirectory(string path) 
        {
            if(path.length == 0)
            {
                return;
            }
            else if(path[$-1] == '/') // Handle paths ending with "/"
            {
                _root.addDirectory(split(path, "/")[0 .. $-1]);
            }
            else
            {
                _root.addDirectory(split(path, "/")); 
            }
        }

        /**
         * Removes a member from the archive.
         */
        public bool removeFile(string path) { return _root.removeFile(split(path, "/")); }
        public bool removeFile(File file) { return _root.removeFile(split(file.path, "/")); }
        
        /**
         * Removes a directory from the archive.
         */
        public bool removeDirectory(string path) 
        { 
            if(path.length == 0)
            {
                return false;
            }
            else if(path[$-1] == '/') // Handle paths ending with "/"
            {
                return _root.removeDirectory(split(path, "/")[0 .. $-1]);
            }
            else
            {
                return _root.removeDirectory(split(path, "/")); 
            }
        }
        
        /**
         * Removes all empty directories from the archive. 
         */
        public void removeEmptyDirectories() { _root.removeEmptyDirectories(); }
    
    }
    
    static if(T.hasProperties)
    {
        @property Properties properties() { return _properties; }
        private Properties _properties;
    }
    private Directory _root;
}

unittest
{
    struct MockPolicy
    {
        public static immutable(bool) isReadOnly = false;
        public static immutable(bool) hasProperties = false;

        public class FileImpl : ArchiveMember 
        { 
            this() { super(false); }
            this(string path) { super(false, path); } 
            this(string[] path) { super(false, path); }
        }
        
        public class DirectoryImpl : ArchiveDirectory!MockPolicy 
        { 
            this() { }
            this(string path) { super(path); } 
            this(string[] path) { super(path); }
        }
        
        public static void deserialize(void[] data, DirectoryImpl root)
        {
        }

        public static void[] serialize(DirectoryImpl root)
        {
            return (cast(void[]) new ubyte[4]);
        }
    }

    struct MockFilter
    {
        public static void[] compress(void[] data)
        {
            return data;
        }

        public static void[] decompress(void[] data)
        {
            return data;
        }
    }
    
    alias ArchType = Archive!(MockPolicy, MockFilter);
    alias File = MockPolicy.FileImpl;
    alias Directory = MockPolicy.DirectoryImpl;
    
    // Archive tests
    ArchType arch = new ArchType();

    // Add top-level member
    arch.addFile(new File("apples.txt"));
   
    // Add member adding in implicit directory. 
    arch.addFile(new File("apples/oranges.txt"));

    // Add member, adding in implicit directory while using one previously defined.
    arch.addFile(new File("apples/oranges/bananas.txt"));

    // Add directory, adding in implicit directory
    arch.addDirectory("animals/dog/");

    // Add directory, using previously defined directory without trailing "/"
    arch.addDirectory("animals/cat");

    // Add directory, adding in implicit directory
    arch.addDirectory("animals/bird/eagle/");

    assert(arch.getFile("apples.txt") !is null);
    assert(arch.getDirectory("apples") !is null);
    assert(arch.getFile("apples/oranges.txt") !is null);
    assert(arch.getDirectory("apples/oranges/") !is null);
    assert(arch.getFile("apples/oranges/bananas.txt") !is null);

    assert(arch.getDirectory("animals") !is null);
    assert(arch.getDirectory("animals/dog/") !is null);
    assert(arch.getDirectory("animals/cat/") !is null);
    assert(arch.getDirectory("animals/bird/") !is null);
    assert(arch.getDirectory("animals/bird/eagle/") !is null);

    // Check the num* is correct
    assert(arch.numFiles() == 3);
    assert(arch.numDirectories() == 7);
    assert(arch.numMembers() == 10);

    // Check num* at top level is correct
    assert(arch.numFiles(0) == 1);
    assert(arch.numDirectories(0) == 2);
    assert(arch.numMembers(0) == 3);
    
    // Check num* at level = 1 is correct
    assert(arch.numFiles(1) == 2);
    assert(arch.numDirectories(1) == 6);
    assert(arch.numMembers(1) == 8);

    // Remove top level member
    arch.removeFile("apples.txt");

    // Remove not-top level member
    arch.removeFile("apples/oranges.txt");

    // Remove top level directory
    arch.removeDirectory("apples/");

    // Remove non top-level directory
    arch.removeDirectory("animals/dog/");

    // Remove All empty directories.
    arch.removeEmptyDirectories();

    assert(arch.root.directories.length == 0);
    assert(arch.root.files.length == 0);
}

unittest
{
    struct MockROPolicy
    {
        public static immutable(bool) isReadOnly = true;
        public static immutable(bool) hasProperties = true;

        public class FileImpl : ArchiveMember 
        { 
            this() { super(false); }
            this(string path) { super(false, path); } 
            this(string[] path) { super(false, path); }
        }

        public class DirectoryImpl : ArchiveDirectory!MockROPolicy 
        {
            this() { super(); }
            this(string path) { super(path); } 
            this(string[] path) { super(path); }
        }
        
        public class Properties { }
        
        public static void deserialize(void[] data, DirectoryImpl root, Properties props)
        {
            char[] cdata = (cast(char[])data);
            assert(std.algorithm.all!"a == 'a'"(cdata));
        }
    }

    struct MockROFilter
    {
        public static void[] decompress(void[] data)
        {
            // Fill it all with a's. We'll test in the deserialize that this is held.
            char[] cdata = (cast(char[])data);
            cdata[] = 'a';
            return data;
        }
    }
    
    alias ArchType = Archive!(MockROPolicy, MockROFilter);

    // Read only archive instantiation tests
    ArchType Arch = new ArchType(['0', '1', '2', '3', '4', '5', '6', '7', '8']);
}
