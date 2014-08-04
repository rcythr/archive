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

/**
 * The common template for all archives. Each archive format is implemented as a Policy class which supplies necessary
 * types and methods specific to that format. Reference this class to find the methods available to all archives, but use
 * the docs for your specific format to find methods/members available for your specific format.
 */
public class Archive(T, Filter = NullArchiveFilter)
{    
    /**
     * Alias to allow for easy referencing the proper archive File member type for Policy.
     */
    alias File = T.FileImpl;
    
    /**
     * Alias to allow for easy referencing the proper archive Directory member type for Policy.
     */
    alias Directory = T.DirectoryImpl;
    
    static if(T.hasProperties)
    {
        /**
        * (Optional) Alias to allow for easy referencing the proper archive Properties type for Policy.
        *       e.g. Tar archives do not have any archive-wide properties, while zip files have an archive comment.
        */
        alias Properties = T.Properties;
    }
    
    /**
    Constructor for archives which initializes the archive with the contents of the serialized archive
    stored in data.
    Params:
        data = serialized data of an archive in the proper format for the Policy.
     */
    public this(void[] data) 
    {
        // Cannot call this() because it may not be defined.
        root = new Directory(); 
        static if(T.hasProperties)
            properties = new Properties();
        T.deserialize(Filter.decompress(data), this);
    }
   
    static if(!T.isReadOnly)
    {
        /**
         * Constructor for read/write archives which does not require serialized data to create.
         */
        public this() 
        { 
            root = new Directory(); 
            static if(T.hasProperties)
                properties = new Properties(); 
        }
    }
    
    /**
     * Provides access to all files in the archive via a delegate method. This allows use in foreach loops.
     * Example:
     * ---
     *    foreach(file; archive.files)
     *    {
     *        // Use properties of file
     *    }
     * ---
     */
    @property public int delegate(int delegate(ref File)) files() { return &root.filesOpApply; }

    /**
     * Provides access to all directories in the archive via a delegate method. This allows use in foreach loops.
     * Example:
     * ---
     *    foreach(dir; archive.directories)
     *    {
     *        // Use properties of dir
     *    }
     * ---
     */
    @property public int delegate(int delegate(ref Directory)) directories() { return &root.directoriesOpApply; }
    
    /**
     * Provides access to all files and directories in the archive via a delegate method. This allows use in foreach loops.
     * Example:
     * ---
     *    foreach(member; archive.members)
     *    {
     *        if(member.isFile())
     *        {
     *            auto file = cast(archive.File)member;
     *            // Use properties of file
     *        }
     *        else
     *        {
     *            auto dir = cast(archive.Directory)member;
     *            // Use properties of dir
     *        }
     *    }
     * ---
     */
    @property public int delegate(int delegate(ref ArchiveMember)) members() { return &root.membersOpApply; }

    /**
     * Returns: The file associated with the given path variable, or null if no such file exists in the archive.
     */
    public File getFile(string path) 
    { 
        return root.getFile(split(path, "/")); 
    }

    /**
     * Returns: The directory associated with the given path variable, the root for "/", or null if no such directory exists.
     */
    public Directory getDirectory(string path) 
    { 
        if(path.length == 0) // Handle ""
        {
            return root;
        }
        else if(path[$-1] == '/') // Handle paths ending with /
        {
            return root.getDirectory(split(path, "/")[0 .. $-1]);
        }
        else // Handle paths ending without /
        {
            return root.getDirectory(split(path, "/")); 
        }
    }

    /**
     * Returns: the number of files in the archive which are up to n levels deep (inclusive).
     */
    public size_t numFiles(size_t n=size_t.max) { return root.numFiles(n); }

    /**
     * Returns: The number of directories in the archive which are up to n levels deep (inclusive).
     */
    public size_t numDirectories(size_t n=size_t.max) { return root.numDirectories(n); }

    /**
     * Returns: The number of directories and files in the archive which are up to n levels deep (inclusive).
     */
    public size_t numMembers(size_t n=size_t.max) { return root.numMembers(n); }

    static if(!T.isReadOnly)
    {
        /**
         * Serializes the archive.
         * Returns: the archive in a void[] array which can be saved to a file, sent over a network connection, etc.
         */
        public void[] serialize() 
        { 
            return Filter.compress(T.serialize(this));
        }   
    }
    
    /**
     * Adds a file to the archive. If the path to the file contains directories that are not in the archive, they are added.
     * Throws: IllegalPathException when an element in the given path is already used for a file/directory or the path is otherwise invalid.
     * Example:
     * ---
     * // inserts apple.txt into the archive.
     * archive.addFile(new archive.File("apple.txt")); 
     *
     * // inserts directory animals (if not exists) and dogs.txt into the archive.
     * archive.addFile(new archive.File("animals/dogs.txt")); 
     * ---
     */
    public void addFile(File member) 
    { 
        if(member.path == null || member.path == "")
            throw new IllegalPathException("Files which are inserted into the archive must have a valid name");
            
        root.addFile(split(member.path, "/"), member); 
    }
    
    /**
     * Adds a directory to the archive. If the path to the directory contains directories that are not in the archive, they are added.
     * If the directory already exists it is not replaced with an empty directory.
     * 
     * Returns: the final Directory in the path. (e.g. "dlang" for "languages/dlang/")
     * Throws: IllegalPathException when an element in the given path is already used for a file or the path is otherwise invalid.
     * Example:
     * ---
     * // inserts animals/birds/ into the archive.
     * archive.addDirectory("animals/"); 
     *
     * // inserts directory languages (if not exists) and dlang into the archive.
     * archive.addDirectory("languages/dlang/"); 
     * ---
     */
    public Directory addDirectory(string path) 
    {
        if(path.length == 0)
        {
            return root;
        }
        else if(path[$-1] == '/') // Handle paths ending with "/"
        {
            return root.addDirectory(split(path, "/")[0 .. $-1]);
        }
        else
        {
            return root.addDirectory(split(path, "/")); 
        }
    }

    /**
     * Removes a file from the archive.
     * Returns: true if the file was removed, false if it did not exist.
     */
    public bool removeFile(string path) { return root.removeFile(split(path, "/")); }

    /**
     * Removes a directory (and all contained files and directories) from the archive.
     * Returns: true if the directory was removed, false if it did not exist.
     */
    public bool removeDirectory(string path) 
    { 
        if(path.length == 0)
        {
            return false;
        }
        else if(path[$-1] == '/') // Handle paths ending with "/"
        {
            return root.removeDirectory(split(path, "/")[0 .. $-1]);
        }
        else
        {
            return root.removeDirectory(split(path, "/")); 
        }
    }

    /**
     * Removes all directories in the archive with no direct files or files in subdirectories.
     */
    public void removeEmptyDirectories() { root.removeEmptyDirectories(); }
    
    static if(T.hasProperties)
    {
        /**
         * (Optional) Archive-wide properties for the format associated with Policy. 
         *      e.g. Tar archives do not have any archive-wide properties, while zip files have an archive comment.
         */
        public Properties properties;
    }
    
    /**
     * The root directory of the archive. Public here to allow for manual recursive algorithms.
     */
    public Directory root;
}

/**
 * Thrown when a supplied path is invalid.
 */
public class IllegalPathException : Exception
{
    this(string msg) { super("IllegalPathException: " ~ msg); }
}

/**
 * Default filter which performs no mutation to the input/output data.
 */
public class NullArchiveFilter
{
    public static void[] compress(void[] data) { return data; }
    public static void[] decompress(void[] data) { return data; }
}

/**
 * Common base class for all Archive members (Files and Directories). 
 * Provides common name management functionality and ability to iterate over both Files and Directories at once.
 */
public class ArchiveMember
{
    private bool _isDirectory;
    protected string _path;
    
    protected this(bool isDirectory)
    {
        _isDirectory = isDirectory;
        _path = "";
    }

    protected this(bool isDirectory, string mypath)
    {
        _isDirectory = isDirectory;
        _path = mypath;
    }

    protected this(bool isDirectory, string[] pathParts)
    {
        _isDirectory = isDirectory;
        _path = join(pathParts, "/");
    }

    /**
     * Returns: true if this member is a directory, false otherwise.
     */
    @property bool isDirectory() { return _isDirectory; }

    /**
     * Returns: false if this member is a file, false otherwise.
     */
    @property bool isFile() { return !_isDirectory; }

    /**
     * Gets the final element in the path of this member.
     *      e.g. for the path "a/b/c/e/fg.txt" the result is "fg.txt"
     * Returns: the final element in the path of this member.
     */
    @property public string name() 
    { 
        string[] parts = split(_path, '/'); 
        return parts[$-1]; 
    }

    /**
     * Sets the final element in the path of this member.
     *      e.g. for the path "a/b/c/e/fg.txt" the changed path part will be "fg.txt"
     * Warning: Do not use this property while this member is currently part of an archive.
     */
    @property public void name(string newname)
    { 
        string[] parts = split(_path, '/'); 
        parts[$-1] = newname; 
        _path = join(parts, "/"); 
    }

    /**
     * Gets the path of this member.
     * Returns: the path of this member.
     */
    @property string path()
    { 
        return _path; 
    }

    /**
     * Sets the path of this member.
     * Warning: Do not use this property while this member is currently part of an archive.
     */
    @property void path(string newpath)
    { 
            _path = newpath; 
    }
}

/**
 * Base class for archive directories. Provides common subdirectory and file management.
 */
public class ArchiveDirectory(Policy) : ArchiveMember
{

    /**
     * Alias for referencing the correct File class in the Policy.
     */
    public alias File = Policy.FileImpl;
    
    /**
     * Alias for referencing the correct Directory class in the Policy.
     */
    public alias Directory = Policy.DirectoryImpl;

    /**
     * Default constructor for ArchiveDirectories. Used to create the root archive. 
     * Note: Do not use without a subsequent call to *at least* .path = "path".
     */
    public this() { super(true, ""); }
 
    /**
     * Constructs a new ArchiveDirectory with the given path name.
     */
    public this(string mypath) { super(true, mypath); }
    
    /** ditto */
    public this(string[] parts) { super(true, parts); }
    
    /*
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
    
    /*
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
   
    /*
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

    /*
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
    
    /*
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
   
    /*
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
    
    /*
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

    /*
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

    /*
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

    /*
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
     * opApply method used for file iteration.
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
     * opApply method used for directory iteration.
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
     * opApply method for member iteration.
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
     * Subdirectories in this directory. Allows access to directories during manual recursion of the Directory structure.
     */
    public Directory[string] directories;

    /**
     * Files in this directory. Allows access to files during manual recursion of the Directory structure.
     */
    public File[string] files;
}

unittest
{
    class MockPolicy
    {
        public static immutable(bool) isReadOnly = false;
        public static immutable(bool) hasProperties = false;

        public class FileImpl : ArchiveMember 
        { 
            public this() { super(false); }
            public this(string path) { super(false, path); } 
            public this(string[] path) { super(false, path); }
        }
        
        public class DirectoryImpl : ArchiveDirectory!(MockPolicy)
        { 
            public this() { }
            public this(string path) { super(path); } 
            public this(string[] path) { super(path); }
        }
        
        public static void deserialize(Filter)(void[] data, Archive!(MockPolicy, Filter) archive)
        {
        }

        public static void[] serialize(Filter)(Archive!(MockPolicy, Filter) archive)
        {
            return (cast(void[]) new ubyte[4]);
        }
    }

    class MockFilter
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
            public this() { super(false); }
            public this(string path) { super(false, path); } 
            public this(string[] path) { super(false, path); }
        }

        public class DirectoryImpl : ArchiveDirectory!MockROPolicy 
        {
            public this() { super(); }
            public this(string path) { super(path); } 
            public this(string[] path) { super(path); }
        }
        
        public class Properties { }
        
        public static void deserialize(Filter)(void[] data, Archive!(MockROPolicy, Filter) archive)
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
