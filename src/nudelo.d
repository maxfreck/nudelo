module nudelo;

import std.stdio: File;

/// Nudelo configuration
struct Config
{
	/// Input file stream
	File inputFile;
	/// Output file stream
	File outputFile;
	/// Javascript processing command
	string[] processJavascript;
	/// CSS processing command
	string[] processCss;
	/// Fix unknown server-side scripts to this value
	string fixUnknown = "";
}

private struct TagItem
{
	string tagName;
	string tagArgs;
	string tagBody;

	pure nothrow string glue() @safe
	{
		if (tagArgs.length == 0) {
			return "<"~tagName~">"~tagBody~"</"~tagName~">";
		}
		return "<"~tagName~" "~tagArgs~">"~tagBody~"</"~tagName~">";
	}
}

private struct ServerScriptItem
{
	string scriptType;
	string scriptBody;

	pure nothrow string glue() @safe
	{
		return "<?"~scriptType~scriptBody~"?>";
	}
}

private string getFileContents(File f) @trusted
{
	import std.array: appender, join;
	immutable fSize = f.size();

	if (fSize == 0) return "";

	if (fSize == ulong.max) {
		//string[] ret;
		auto ret = appender!(string[]);
		foreach (line; f.byLine) ret ~= line.idup;
		return ret.data.join;
	}

	auto buffer = new ubyte[cast(size_t)(fSize)];
	f.rawRead(buffer);
	return cast(string)(buffer);
}

/// minifies html file
void minify(Config cfg) @safe
{
	import std.array: replace;
	import std.regex: ctRegex, regex, replaceAll, replaceFirst;

	if (cfg.inputFile.size == 0 || cfg.inputFile.size == ulong.max) {
		return;
	}

	string htmlContent = cfg.inputFile.getFileContents();

	ServerScriptItem[] server;
	TagItem[] pre;
	TagItem[] script;
	TagItem[] style;

	htmlContent = htmlContent.stripServerScripts(server);

	htmlContent = htmlContent.stripTag!("pre")(pre);
	htmlContent = htmlContent.stripTag!("script")(script);
	htmlContent = htmlContent.stripTag!("style")(style);

	htmlContent = htmlContent
		.replaceChars(['\r', '\n', '\t'], [' ', ' ', ' ']) //replace line feeds and tabs with spaces
		.replaceAll(ctRegex!(r"<!--[^\[].+?-->"), "") //delete all comments except conditional
		.replace(" >", ">")
		.replaceAll(ctRegex!(r" +"), " ")

		.replaceAll(regex(r"\s*<(?!(\/|a|abbr|acronym|b|bdi|bdo|big|button|cite|code|del|dfn|em|font|i|ins|kbd|mark|math|nobr|q|rt|rp|s|samp|small|span|strike|strong|sub|sup|svg|time|tt|u|var))(.*?)>\s*"), "<$1$2>")

		.replaceFirst(ctRegex!(r"^(<!DOCTYPE.+?>)"), "$1\n")
	;

	if (style.length > 0) {
		if (cfg.processCss.length != 0 ) {
			style.processTags(cfg.processCss);
		}
		htmlContent = htmlContent.insertTag!("style")(style);
	}

	if (script.length > 0) {
		if (cfg.processJavascript.length != 0 ) {
			script.processTags(cfg.processJavascript);
		}
		htmlContent = htmlContent.insertTag!("script")(script);
	}

	if (pre.length > 0) htmlContent = htmlContent.insertTag!("pre")(pre);

	if (server.length > 0) {
		if (cfg.fixUnknown.length != 0) {
			server.fixServerScripts(cfg.fixUnknown);
		}
		htmlContent = htmlContent.insertServerScripts(server);
	}

	cfg.outputFile.write(htmlContent);
}

private string stripServerScripts(string str, ref ServerScriptItem[] pocket) @safe
{
	import std.array: replace;
	import std.conv: to;
	import std.regex: ctRegex, matchAll, regex, replaceAll;

	foreach (m; matchAll(str, regex(r"<\?(=|\p{L}*)(.+?)\?>","s")))
	{
		pocket ~= ServerScriptItem(m[1], m[2]);
		str = str.replace(m[0], "[SERVER:"~to!string(pocket.length)~"]");
	}

	return str;
}


private string insertServerScripts(string str, ServerScriptItem[] pocket) @safe
{
	import std.array: replace;
	import std.conv: to;

	for (size_t i = 0; i < pocket.length; i++ )
	{
		str = str.replace("[SERVER:"~to!string(i+1)~"]", pocket[i].glue);
	}

	return str;
}
private void fixServerScripts(ServerScriptItem[] pocket, string fix) @safe
{
	foreach(ref s; pocket) {
		if (s.scriptType.length == 0 ) {
			s.scriptType = fix;
		}
	}
}


private @safe string stripTag(string TAG)(string str, ref TagItem[] pocket)
{
	import std.array: replace;
	import std.conv: to;
	import std.regex: ctRegex, matchAll, regex, replaceAll;
	import std.string: strip;


	foreach (m; matchAll(str, regex(r"<"~TAG~"(\\b[^>]*)>([\\s\\S]*?)<\\/"~TAG~">","s"))) {
		if (m.length < 3 || m[2].length == 0) continue;
		pocket ~= TagItem(
			TAG,
			m[1].replaceAll(ctRegex!(r" +"), " ").strip,
			m[2]
		);
		str = str.replace(m[0], "["~TAG~"#"~to!string(pocket.length)~"]");
	}

	return str;
}

private string insertTag(string TAG)(string str, TagItem[] pocket)
{
	import std.array: replace;
	import std.conv: to;

	for (size_t i = 0; i < pocket.length; i++ ) {
		str = str.replace("["~TAG~"#"~to!string(i+1)~"]", pocket[i].glue);
	}

	return str;
}

private string replaceChars(string src, char[] from, char[] to) @trusted
{
	auto str = cast(ubyte[])(src);
	foreach (ref c; str) {
		for (size_t i = 0; i < from.length; i++) {
			if (c == from[i]) c = to[i];
		}
	}
	return cast(string)(str);
}

private void processTags(ref TagItem[] js, string[] command) @safe
{
	import std.array: join;
	import std.process: pipeProcess, wait;

	foreach (ref tag; js) {
		auto pipes = pipeProcess(command);
		pipes.stdin.write(tag.tagBody);
		pipes.stdin.flush();
		pipes.stdin.close();

		immutable ret = wait(pipes.pid);
		if (ret == 0) {
			tag.tagBody = pipes.stdout.getFileContents();
		} else {
			reportErrorTag(command.join(), tag.tagBody, pipes.stderr);
		}
	}
}

private void reportErrorTag(string command, string src, File err) @trusted
{
	import std.algorithm.iteration: each;
	import std.stdio: stderr, writefln, writeln;
	import std.string: lineSplitter;

	writefln("--- '%s' error:", command);
	lineSplitter(src).each!(s => stderr.writeln("> ", s));
	stderr.writeln("\n", err.getFileContents(), "\n");
}