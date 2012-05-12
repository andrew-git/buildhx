package buildhx;


import neko.FileSystem;
import neko.io.File;
import neko.io.Path;
import neko.Lib;
import neko.Sys;
import haxe.xml.Fast;

import buildhx.data.ClassDefinition;
import buildhx.data.ClassMethod;
import buildhx.data.ClassProperty;
import hxjson2.JSON;
import neko.FileSystem;
import neko.io.File;
import neko.io.Path;
import neko.Lib;
import buildhx.parsers.AbstractParser;
import buildhx.parsers.JSDuckParser;


class BuildHX {
	
	
	public static var isMac = false;
	public static var isLinux = false;
	public static var isWindows = false;
	public static var buildhx:String = "";
	public static var traceEnabled:Bool = true;
	public static var verbose = false;
	
	private static var restrictedNames:Array < String > = [ "callback", "extern", "class", "override", "static", "public", "private", "enum" ];
	
	private static var parser:AbstractParser;
	private static var parserName:String;
	private static var sourcePath:String;
	private static var targetFlags:Hash <String>;
	private static var targetPath:String;
	
	private static var definitions:Hash <ClassDefinition>;
	private static var types:Hash <String>;
	
	
	private static function argumentError (error:String):Void {
		
		Lib.println (error);
		Lib.println ("Usage :  haxelib run buildhx COMMAND ...");
		Lib.println (" COMMAND : externs sourcePath targetPath");
		
	}
	
	
	public static function copyIfNewer (source:String, destination:String) {
		
		if (!isNewer (source, destination)) {
			
			return;
			
		}
		
		if (verbose) {
			
			Lib.println ("Copy " + source + " to " + destination);
			
		}
		
		File.copy (source, destination);
		
	}
	
	
	public static function error (message:String):Void {
		
		Lib.println ("Error: " + message);
		Sys.exit ( -1);
		
	}
	
	
	public static function getNeko ():String {
		
		var path:String = Sys.getEnv ("NEKO_INSTPATH");
		
		if (path == null || path == "") {
			
			path = Sys.getEnv ("NEKO_INSTALL_PATH");
			
		}
		
		if (path == null || path == "") {
			
			path = Sys.getEnv ("NEKOPATH");
			
		}
		
		if (path == null || path == "") {
			
			if (Sys.systemName () == "windows") {
				
				path = "C:/Motion-Twin/neko";
				
			} else {
				
				path = "/usr/lib/neko";
				
			}
			
		}
		
		return path + "/";
		
	}
	
	
	public static function isNewer (source:String, destination:String):Bool {
		
		if (source == null || !FileSystem.exists (source)) {
			
			throw ("Error: " + source + " does not exist");
			return false;
			
		}
		
		if (FileSystem.exists (destination)) {
			
			if (FileSystem.stat (source).mtime.getTime () < FileSystem.stat (destination).mtime.getTime ()) {
				
				return false;
				
			}
			
		}
		
		return true;
		
	}
	
	
	public static function print (message:String, requireVerbose:Bool = false):Void {
		
		if (!requireVerbose || verbose) {
			
			Lib.println (message);
			
		}
		
	}
	

	public static function runCommand (path:String, command:String, args:Array<String>) {
		
		var oldPath:String = "";
		
		if (path != "") {
			
			print("cd " + path);
			
			oldPath = Sys.getCwd ();
			Sys.setCwd (path);
			
		}
		
		print(command + (args==null ? "": " " + args.join(" ")) );
		
		var result:Dynamic = Sys.command (command, args);
		
		if (result == 0)
			print("Ok.");
			
		
		if (oldPath != "") {
			
			Sys.setCwd (oldPath);
			
		}
		
		if (result != 0) {
			
			throw ("Error running: " + command + " " + args.join (" ") + path);
			
		}
		
	}
	
	
	public static function main () {
		
		var inputFile:String = "";
		var debug:Bool = false;
		var defines = new Hash <String> ();
		var includePaths = new Array <String> ();
		var targetFlags = new Hash <String> ();
		
		includePaths.push (".");
		
		var args:Array <String> = Sys.args ();
		
		if (args.length > 0) {
			
			// When called from haxelib, the last argument is the calling directory. The path to buildhx is set as the current working directory 
			
			var lastArgument:String = new Path (args[args.length - 1]).toString ();
			
			if (lastArgument.substr (-1) == "/" || lastArgument.substr (-1) == "\\") {
				
				lastArgument = lastArgument.substr (0, lastArgument.length - 1);
				
			}
			
			if (FileSystem.exists (lastArgument) && FileSystem.isDirectory (lastArgument)) {
				
				buildhx = Sys.getCwd ();
				var last = buildhx.substr(-1,1);
				if (last=="/" || last=="\\")
					buildhx = buildhx.substr(0,-1);
				Sys.setCwd (lastArgument);
				
				defines.set ("BUILDHX", buildhx);
				args.pop ();
				
			}
			
		}
		
		if (new EReg ("window", "i").match (Sys.systemName ())) {
			
			defines.set ("windows", "1");
			defines.set ("BUILDHX_HOST", "windows");
			isWindows = true;
			
		} else if (new EReg ("linux", "i").match (Sys.systemName ())) {
			
			defines.set ("linux", "1");
			defines.set ("BUILDHX_HOST", "linux");
			isLinux = true;
			
		} else if (new EReg ("mac", "i").match (Sys.systemName ())) {
			
			defines.set ("macos", "1");
			defines.set ("BUILDHX_HOST", "darwin-x86");
			isMac = true;
			
		}
		
		var words:Array <String> = new Array <String> ();
		
		for (arg in args) {
			
			var equals:Int = arg.indexOf ("=");
			
			if (equals > 0) {
				
				defines.set (arg.substr (0, equals), arg.substr (equals + 1));
				
			} else if (arg == "-v" || arg == "-verbose") {
				
				verbose = true;
				
			} else if (arg.substr (0, 2) == "-D") {
				
				defines.set (arg.substr (2), "");
				
			} else if (arg.substr (0, 2) == "-l") {
				
				includePaths.push (arg.substr (2));
				
			} else if (arg == "-debug") {
				
				debug = true;
				defines.set ("debug", "");
				
			} else if (inputFile.length == 0) {
				
				inputFile = arg;
				
			} else if (arg.substr (0, 1) == "-") {
				
				targetFlags.set (arg.substr (1), "");
				
			} else {
				
				words.push (arg);
				
			}
			
		}
		
		/*if (Sys.environment ().exists ("HOME")) {
			
			includePaths.push (Sys.getEnv ("HOME"));
			
		}
		
		if (Sys.environment ().exists ("USERPROFILE")) {
			
			includePaths.push (Sys.getEnv ("USERPROFILE"));
			
		}*/
		
		//includePaths.push (buildhx + "/src");
		
		if (inputFile == "") {
			
			Lib.println ("BuildHX (1.0.0)");
			Lib.println ("Usage : haxelib run buildhx Build.xml");
			return;
			
		}
		
		
		if (!FileSystem.exists (inputFile)) {
			
			if (FileSystem.exists (FileSystem.fullPath (inputFile))) {
				
				inputFile = FileSystem.fullPath (inputFile);
				
			} else {
				
				error ("Input file \"" + inputFile + "\" does not exist");
				
			}
			
		}
		
		var xml:Fast = null;
		
		try {
			
			xml = new Fast (Xml.parse (File.getContent (inputFile)).firstElement ());
			
		} catch (e:Dynamic) {
			
			error ("\"" + inputFile + "\" contains invalid XML data");
			
		}
		
		parseXML (xml);
		
		switch (parserName) {
			
			case "jsduck":
				
				parser = new JSDuckParser (types, definitions);
			
			default:
				
				error ("\"" + parserName + "\" is an unknown parser type");
			
		}
		
		generateExterns ();
		
	}
	
	
	public static function generateExterns () {
		
		if (Std.is (parser, JSDuckParser)) {
			
			runCommand ("", buildhx + "/bin/jsduck-3.10.1.exe", [ sourcePath, "--export=full", "--output", "obj", "--pretty-json" ]);
			sourcePath = FileSystem.fullPath ("obj") + "/";
			
		}
		
		parser.processFiles (FileSystem.readDirectory (sourcePath), sourcePath);
		parser.resolveClasses ();
		parser.writeClasses (targetPath);
		
	}
	
	
	public static function addImport (type:String, definition:ClassDefinition):Void {
		
		if (type != null && type != "" && type.substr (-1) != ".") {
			
			definition.imports.set (type, type);
			
		}
		
	}
	
	
	public static function alphabeticalSorting (s1:String, s2:String):Int {
		
		var desc = false;
		if (s1 == s2) return 0;
		s1 = s1.toLowerCase ();
		s2 = s2.toLowerCase ();
		for (i in 0...s1.length)
		{
			var n1 : Int = s1.charCodeAt (i);
			var n2 : Int = s2.charCodeAt (i);
			if (n1 < n2)
				return (desc ? 1 : -1); // If descending, the other way around
			else if (n2 < n1)
				return (desc ? -1 : 1);
		}
		return (s1.length < s2.length ? (desc ? 1 : -1) : (desc ? -1 : 1));
		
	}
	
	
	public static function getFileContent (file:String):String {
		
		return File.getContent (file);
		
	}
	
	
	public static function isRestrictedName (name:String):Bool {
		
		for (restrictedName in restrictedNames) {
			
			if (name == restrictedName) {
				
				return true;
				
			}
			
		}
		
		return false;
		
	}
	
	
	public static function makeDirectory (targetPath:String):Void {
		
		var directory = Path.directory (targetPath);
		
		var total = "";
		
		if (directory.substr (0, 1) == "/") {
			
			total = "/";
			
		}
		
		var parts = directory.split ("/");
		
		for (part in parts) {
			
			if (part != "." && part != "") {
				
				if (total != "") {
					
					total += "/";
					
				}
				
				total += part;
				
				if (!FileSystem.exists (total)) {
					
					print ("Creating directory " + total, true);
					
					FileSystem.createDirectory (total);
					
				}
				
			}
			
		}
		
	}
	
	
	public static function parseJSON (content:String):Dynamic {
		
		return JSON.decode (content, false);
		
	}
	
	
	private static function parseClassElement (element:Fast):Void {
		
		var definition = new ClassDefinition ();
		
		definition.className = element.att.name;
		
		if (element.has.ignore && element.att.ignore == "true") {
			
			definition.ignore = true;
			
		}
		
		if (element.has.parent) {
			
			definition.parentClassName = element.att.parent;
			
		}
		
		if (element.has.config && element.att.config == "true") {
			
			definition.isConfigClass = true;
			
		}
		
		for (childElement in element.elements) {
			
			switch (childElement.name) {
				
				case "import":
					
					definition.imports.set (childElement.att.name, childElement.att.name);
				
				case "property":
					
					var property = new ClassProperty ();
					
					property.name = childElement.att.name;
					property.type = childElement.att.type;
					
					if (childElement.has.ignore && childElement.att.ignore == "true") {
						
						property.ignore = true;
						
					}
					
					if (childElement.has.owner) {
						
						property.owner = childElement.att.owner;
						
					} else {
						
						property.owner = definition.className;
						
					}
					
					if (childElement.has.resolve ("static") && childElement.att.resolve ("static") == "true") {
						
						definition.staticProperties.set (property.name, property);
						
					} else {
						
						definition.properties.set (property.name, property);
						
					}
				
				case "method":
					
					var method = new ClassMethod ();
					
					method.name = childElement.att.name;
					
					if (childElement.has.ignore && childElement.att.ignore == "true") {
						
						method.ignore = true;
						
					}
					
					if (childElement.has.owner) {
						
						method.owner = childElement.att.owner;
						
					} else {
						
						method.owner = definition.className;
						
					}
					
					for (methodElement in childElement.elements) {
						
						if (methodElement.name == "parameter") {
							
							method.parameterNames.push (methodElement.att.name);
							method.parameterTypes.push (methodElement.att.type);
							
							if (methodElement.has.optional && methodElement.att.optional == "true") {
								
								method.parameterOptional.push (true);
								
							} else {
								
								method.parameterOptional.push (false);
								
							}
							
						} else if (methodElement.name == "return") {
							
							method.returnType = methodElement.att.type;
							
						}
						
					}
					
					if (childElement.has.resolve ("static") && childElement.att.resolve ("static") == "true") {
						
						definition.staticMethods.set (method.name, method);
						
					} else {
						
						definition.methods.set (method.name, method);
						
					}
				
			}
			
		}
		
		definitions.set (definition.className, definition);
		
	}
	
	
	private static function parseXML (xml:Fast):Void {
		
		types = new Hash <String> ();
		definitions = new Hash <ClassDefinition> ();
		
		for (element in xml.elements) {
			
			switch (element.name) {
				
				case "source":
					
					sourcePath = element.att.path;
					
					if (sourcePath == "") {
						
						sourcePath = Sys.getCwd ();
						
					}
					
					if (!FileSystem.exists (sourcePath)) {
						
						sourcePath = FileSystem.fullPath (sourcePath);
						
					}
					
					parserName = element.att.parser;
				
				case "type":
					
					if (element.has.remap) {
						
						types.set (element.att.name, element.att.remap);
						
					} else {
						
						types.set (element.att.name, element.att.name);
						
					}
				
				case "class":
					
					parseClassElement (element);
				
				case "output":
					
					targetPath = element.att.path;
					
					if (targetPath == "") {
						
						targetPath = Sys.getCwd ();
						
					}
					
					if (!FileSystem.exists (targetPath)) {
						
						targetPath = FileSystem.fullPath (targetPath);
						
					}
				
			}
			
		}
		
	}
	
	
	public static function resolveClassName (content:String):String {
		
		var className = content.substr (content.lastIndexOf (".") + 1);
		return className.substr (0, 1).toUpperCase () + className.substr (1);
		
	}
	
	
	public static function resolvePackageName (content:String):String {
		
		if (content.indexOf (".") > -1) {
			
			return content.toLowerCase ().substr (0, content.lastIndexOf ("."));
			
		} else {
			
			return "";
			
		}
		
	}
	
	
	public static function resolvePackageNameDot (content:String):String {
		
		if (content.indexOf (".") > -1) {
			
			return content.toLowerCase ().substr (0, content.lastIndexOf (".") + 1);
			
		} else {
			
			return "";
			
		}
		
	}
	
	
}