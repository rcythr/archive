static import std.file;
import std.stdio;

import archive.core;
import archive.targz;
import archive.tar;
import archive.zip;

enum ArchiveType
{
	zip,
	tar,
	targz
}

void listFiles(T, Filter)(Archive!(T, Filter) archiveT)
{
	foreach (memberFile; archiveT.files)
		writeln(memberFile.path);
}

ArchiveType determineArchiveType(ubyte[] magic)
{
	// TODO: Better check for targz
	if (magic.length >= 4 && magic[0 .. 4] == [0x50, 0x4b, 0x03, 0x04])
		return ArchiveType.zip;
	else if (magic.length >= 262 && magic[257 .. 262] == cast(ubyte[5]) "ustar")
		return ArchiveType.tar;
	else
		return ArchiveType.targz;
}

void main(string[] args)
{
	// remove executable from arguments
	args = args[1 .. $];

	foreach (archivePath; args)
	{
		if (!std.file.exists(archivePath))
			continue;
		// uses first 270 bytes to determine type of archive
		auto file = File(archivePath, "rb");
		ubyte[] magic = new ubyte[270];
		magic = file.rawRead(magic);
		auto type = magic.determineArchiveType;
		final switch (type)
		{
		case ArchiveType.zip:
			auto zip = new ZipArchive(std.file.read(archivePath));
			zip.listFiles();
			break;
		case ArchiveType.tar:
			auto tar = new TarArchive(std.file.read(archivePath));
			tar.listFiles();
			break;
		case ArchiveType.targz:
			auto targz = new TarGzArchive(std.file.read(archivePath));
			targz.listFiles();
			break;
		}
	}
}
