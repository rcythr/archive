#Archive

Archive reading/writing library written entirely in D that currently supports 

+ tar
+ targz  (with underlying gz implementation from zlib)
+ zip

## Full Examples (in depth usage below)

### Archive Reading

Because of the shared Archive template class the same mechanisms hold true for reading:

    import archive.tar;
    import archive.targz;
    import archive.zip;
    import std.stdio;

    auto tar = new TarArchive(std.file.read("my.tar"));
    auto targz = new TarGzArchive(std.file.read("my.tar.gz"));
    auto zip = new ZipArchive(std.file.read("my.zip"));

    // Here are examples of each different available iteration strategy.
    // All are, of course, available for each archive format.
    foreach(file; tar.files)
    {
        writeln(file.path); // Full path
        writeln(file.name); // Just the final name (e.g. "dog.txt" in the path "animals/types/dog.txt")
        writeln(cast(string)file.data); // The actual file data as immutable(ubyte)[].
    }

    foreach(dir; targz.directores)
    {
        writeln(dir.path); // As above
        writeln(dir.name); // As above
        // No data associated with directories.
    }

    foreach(member; zip.members)
    {
        if(member.isDirectory())
        {
            auto dir = cast(ZipArchive.Directory)member;
            writeln(dir.path, dir.name); // As above
            // No data associated with directories.
        }
        else
        {
            auto file = cast(ZipArchive.File)member;
            writeln(file.path, file.name, cast(string)file.data);
        }
    }

### Archive Writing

    import archive.tar;
    import archive.targz;
    import archive.zip;

    auto tar = new TarArchive();
    auto targz = new TarGzArchive();
    auto zip = new ZipArchive();

    // Prep some data behand for clarity.
    string dogData = "Beagle\nBloodhound\nDachshund\nLab\nMastiff\nAND MORE!!";
    string catData = "Australian Mist\nAmerican Shorthair\nKorat\nSnowshoe\nTiger\nAND MORE!!"
    immutable(ubyte)[] rawData = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    
    auto dogs = new TarArchive.File("animals/pets/dogs.txt");
    dogs.data = dogData;
    tar.addFile(dogs);
    
    tar.addDirectory("a/really/deep/empty/directory/branch/");
    
    auto cats = new TarGzArchive.File("animals/pets/cats.txt");
    cats.data = catData;
    targz.addFile(cats);
    
    targz.addDirectory("trailing/slash/is/optional");
    
    auto raw = new ZipArchive.File("some/raw/data.txt");
    raw.data = rawData;
    zip.addFile(raw);
    
    zip.addDirectory("however/all/slashes/are/like/this/never/windows/");
    
    // Changed my mind about adding all those empty directories
    zip.removeEmptyDirectories();
    
    std.file.write("dogs.tar", cast(ubyte[])dogs.serialize());
    std.file.write("cats.tar.gz", cast(ubyte[])cats.serialize());
    std.file.write("raw.zip", cast(ubyte[])raw.serialize());

##Usage

### Reading from an archive

To write to an archive, simply choose the appropriate archive policy. The following example uses the zip policy:

    import archive.zip;

    ZipArchive archive = new ZipArchive(std.file.read("my.zip"));

    // Use archive here.

### Accessing archive members

The most important feature of any archive library is accessing the members of the archive after it has been loaded. The archive template makes this easy:

#### File access

    archive.getFile("path/to/file.txt"); // either ZipArchive.File or null

#### Directory access

    archive.getDirectory("path/to/directory/"); // ZipArchive.Directory or null

Note: the trailing slash in directory names is always optional; however, it is preferred to add it for clarity.

### Iterating through an archive

#### For each iteration

It is possible to iterate through an archive's files with **.files**:

    // Read or create a new archive
    foreach(file; archive.files) // file has type ZipArchive.File
    {
        writeln(file.path);
        writeln(file.data);
        // Print or use other members available with ZipArchive.File class.
    }

It is also possible to iterate through an archive's directories with **.directories**:

    // Read or create a new archive
    foreach(dir; archive.directores) // dir has type ZipArchive.Directory
    {
        writeln(dir.path);
        // Print or use other members available with ZipArchive.Directory class.
    }

Finally, it is possible to iterate through both files and directories with **.members**:

    // Read or create a new archive
    foreach(member; archive.members) // member given as the ArchiveMember base class, but is either ZipArchive.File or ZipArchive.Directory
    {
        if(member.isFile) // member.isDirectory is also available.
        {
             auto file = cast(ZipArchive.File)member;
             // Use members of ZipArchive.File as in previous foreach.
        }
        else
        {
             auto dir = cast(ZipArchive.Directory)member;
             // Use members of ZipArchive.Directory as in previous foreach.
        }
    }

#### Recursive access via .root
It is also possible to do the recursion through the data structure yourself with **.root.**

    void doRec(ZipArchive.Directory dir)
    {
        foreach(file; dir.files)
        {
            writeln("File: ", file.path);
        }
        foreach(dir; dir.directories)
        {
            writeln("Directory: ", dir.path);
            doRec(dir);
        }
    }

    doRec(archive.root);

### Archive modification

The other important feature of an archive library is modification. This functionality is available for all archive formats which are supported for writing (currently all formats). For other formats these functions will not be on the archive interface as they are removed via static if checks.

#### Adding a file

Adding a file is a simple operation. Simply create the file with the proper path and data:

    string apples = "GRANNY SMITH\nMACINTOSH\nGALA\nRED DELICIOUS\nETC";
    immutable(ubyte)[] rawdata = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    // Path can be specified as an argument or in a later assignment to member.
    auto file1 = new ZipArchive.File();

    // If the data directory does not already exist in the archive it will be created on insertion.
    auto file2 = new ZipArchive.File("data/raw.txt");

    file1.path = "apples.txt"
    file1.data = apples; // data can take type string
    archive.addFile(file1);

    file2.data = rawdata; // It can also take an immutable ubyte array.
    archive.addFile(file2);

#### Adding a directory

Adding a directory is even easier. Just call the addDirectory function with the path.

    archive.addDirectory("dir"); 
    archive.addDirectory("a/b/c/d/e/f/g/"); // Creating a sub directory creates all parent directories automatically.
    archive.addDirectory("a/b/c"); // Re-creating a directory is ignored.

#### Removing a file

Removing a file is simple. Just specify the path to the file. If it exists, it will be removed.

    archive.removeFile("animals/birds/blue_jay.txt");

#### Removing a directory

Removing a directory is just as simple. Just call removeDirectory with the path.

    archive.removeDirectory("apple/macintosh/");

Note: Removing a directory will remove all subdirectories and files. Be careful about doing this.

#### Removing all empty directories

One common operation is to remove all directories that are empty. Example:

    archive.removeEmptyDirectories();

### Properties
Some archive formats support file properties which are not associated with specific members. These variables are available via **.properties**

Archive formats that do not contain properties will lack the **.properties**  member, do not allocate a **Properties** class, and consume no additional resources due to static if checks.

    auto archive = new ZipArchive(std.file.read("my.zip"));
    writeln(archive.properties.comment);

### Writing to an archive

Writing to an archive is just as simple as reading from one:

    import archive.tar;
    
    TarArchive archive = new TarArchive();

    // Insert some stuff here

    std.file.write("my.tar", cast(ubyte[])archive.serialize());

