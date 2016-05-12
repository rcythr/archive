static import std.file;
import std.path;
import std.stdio;
import std.string;

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

string extension(ArchiveType type)
{
	final switch (type)
	{
	case ArchiveType.zip:
		return ".zip";
	case ArchiveType.tar:
		return ".tar";
	case ArchiveType.targz:
		return ".tar.gz";
	}
}

void convertTo(T, Filter)(Archive!(T, Filter) archiveT, ArchiveType type, string name)
{
	final switch (type)
	{
	case ArchiveType.zip:
		archiveT.convert(new ZipArchive(), name);
		break;
	case ArchiveType.tar:
		archiveT.convert(new TarArchive(), name);
		break;
	case ArchiveType.targz:
		archiveT.convert(new TarGzArchive(), name);
		break;
	}
}

void convert(T, Filter, U, Filter2)(Archive!(T, Filter) archiveT, Archive!(U,
		Filter2) targetT, string name)
{
	foreach (file; archiveT.files)
	{
		writeln("Converting file ", file.path);
		auto newFile = new Archive!(U, Filter2).File(file.path);
		newFile.data = file.data;
		targetT.addFile(newFile);
	}
	writeln("Outputting to ", name);
	std.file.write(name, targetT.serialize());
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
	if (args.length < 3)
	{
		writeln("Usage: ", args[0], " <zip/tar/targz> <files...>");
		return;
	}

	ArchiveType targetType;
	switch (args[1].strip.toLower)
	{
	case "zip":
		targetType = ArchiveType.zip;
		break;
	case "tar":
		targetType = ArchiveType.tar;
		break;
	case "targz":
		targetType = ArchiveType.targz;
		break;
	default:
		writeln("Usage: ", args[0], " <zip/tar/targz> <files...>");
		return;
	}
	// remove executable & type from arguments
	args = args[2 .. $];

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
			zip.convertTo(targetType, archivePath.stripExtension ~ targetType.extension);
			break;
		case ArchiveType.tar:
			auto tar = new TarArchive(std.file.read(archivePath));
			tar.convertTo(targetType, archivePath.stripExtension ~ targetType.extension);
			break;
		case ArchiveType.targz:
			auto targz = new TarGzArchive(std.file.read(archivePath));
			targz.convertTo(targetType, archivePath.stripExtension ~ targetType.extension);
			break;
		}
	}
}
