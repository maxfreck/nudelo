module main;


int main(string[] args)
{
	import nudelo: Config, minify;

	import std.array: split;
	import std.getopt: defaultGetoptPrinter, getopt;
	import std.stdio:File, stderr, stdin, stdout, writeln;


	try {
		Config cfg;

		string sourceFile = "";
		string destFile = "";
		string cssProcessor = "";
		string jsProcessor = "";

		auto res = getopt(args,
			"input|i", "input file name", &sourceFile,
			"output|o", "output file name", &destFile,
			"process-css|css", "specifies programm to process css", &cssProcessor,
			"process-js|js", "specifies programm to process javascript", &jsProcessor,
			"fix-unknown|f", "fix unknown server-side scripts open tag", &cfg.fixUnknown
		);

		if (res.helpWanted) {
			defaultGetoptPrinter("\nUsage: nudelo [options]\n\nOptions:", res.options);
			return 0;
		}

		if (cssProcessor.length != 0) {
			cfg.processCss = split(cssProcessor);
		}
		if (jsProcessor.length != 0) {
			cfg.processJavascript = split(jsProcessor);
		}
		cfg.inputFile = sourceFile.length == 0 ? stdin : File(sourceFile, "rb");
		cfg.outputFile = destFile.length == 0 ? stdout : File(destFile, "wb");

		cfg.minify();

		return 0;

	} catch (Throwable e) {
		stderr.writeln(e.msg);
		return -1;
	}
}
