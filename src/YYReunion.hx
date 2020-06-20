package;

import haxe.CallStack;
import haxe.Json;
import haxe.io.Path;
import yy.*;
import sys.FileSystem;
import sys.io.File;
import yy.YyProjectResource.YyProjectResourceValue;

/**
 * ...
 * @author YellowAfterlife
 */
class YYReunion {
	static inline var reunionFolderName:String = "reunion";
	static function impl(yypPath:String) {
		var yypName = Path.withoutDirectory(yypPath);
		var dir = Path.directory(yypPath);
		var yyp:YyProject = Json.parse(File.getContent(yypPath));
		//
		var purgeMap:Map<YyGUID, String> = new Map();
		//
		var resourceMap:Map<YyGUID, YyResourceExt> = new Map();
		var resourceList:Array<YyResourceExt> = [];
		var resPathMap:Map<String, YyResourceExt> = new Map();
		function addResource(rx:YyResourceExt) {
			resourceMap[rx.key] = rx;
			resPathMap[rx.val.resourcePath] = rx;
			resourceList.push(rx);
		}
		//
		var viewMap:Map<YyGUID, YyViewExt> = new Map();
		var viewList:Array<YyViewExt> = [];
		function addView(vx:YyViewExt) {
			viewMap[vx.key] = vx;
			viewList.push(vx);
			addResource(vx);
		}
		var rootView:YyViewExt = null;
		//
		var rpi = 0;
		var yypChanged = false;
		var yypNeedsSorting = false;
		inline function addToYYP(rp:YyProjectResource) {
			yyp.resources.push(rp);
			yypNeedsSorting = true;
			yypChanged = true;
		}
		//
		while (rpi < yyp.resources.length) {
			var rp = yyp.resources[rpi];
			var rk = rp.Key;
			var rv:YyProjectResourceValue = rp.Value;
			var rvRel = rv.resourcePath;
			var rvFull = Path.join([dir, rvRel]);
			if (!FileSystem.exists(rvFull)) {
				yyp.resources.splice(rpi, 1);
				yypChanged = true;
				purgeMap[rk] = rvRel;
				Sys.println('Removed missing resource `$rvRel` from YYP.');
				continue;
			}
			if (rv.resourceType == "GMFolder") {
				var vd:YyView = try {
					Json.parse(File.getContent(rvFull));
				} catch (x:Dynamic) {
					yyp.resources.splice(rpi, 1);
					purgeMap[rk] = rvRel;
					Sys.println('`$rvRel` is malformed ($x).');
					continue;
				};
				var vx = new YyViewExt(rk, rv, vd);
				if (vd.isDefaultView) {
					if (rootView == null) {
						rootView = vx;
					} else {
						vd.isDefaultView = false;
						vd.children.resize(0);
						vx.changed = true;
						Sys.println('Secondary root view detected `$rvRel`, original is '
							+ rootView.val.resourcePath);
					}
				}
				addView(vx);
			} else {
				var rx = new YyResourceExt(rk, rv);
				addResource(rx);
			}
			rpi += 1;
		}
		// add missing views:
		for (vrel in FileSystem.readDirectory(Path.join([dir, "views"]))) {
			if (Path.extension(vrel) != "yy") continue;
			var vid_s = Path.withoutExtension(vrel);
			if (!YyGUID.test.match(vid_s)) continue;
			var vid:YyGUID = cast vid_s;
			if (viewMap.exists(vid)) continue;
			//
			var rvRel = 'views\\' + vrel;
			var rvFull = Path.join([dir, rvRel]);
			var vd:YyView = try {
				YYJSON.getContent(rvFull);
			} catch (x:Dynamic) {
				Sys.println('`$rvRel` is malformed ($x).');
				// cleanup?
				continue;
			};
			//
			var rp:YyProjectResource = {
				Key: vid,
				Value: {
					id: new YyGUID(),
					resourcePath: rvRel,
					resourceType: 'GMFolder',
				},
			};
			var vx = new YyViewExt(vid, rp.Value, vd);
			if (vx.ignore) continue;
			addView(vx);
			//
			if (vd.isDefaultView) {
				if (rootView == null) {
					rootView = vx;
				} else {
					vd.isDefaultView = false;
					vd.children.resize(0);
					vx.changed = true;
					Sys.println('Secondary root view detected `$rvRel`, original is '
							+ rootView.val.resourcePath);
				}
			}
			//
			addToYYP(rp);
			Sys.println('Added view `${vd.folderName}` ($vid) back to YYP.');
		}
		if (rootView == null) {
			Sys.println("The project has no root view! You might want to create a new YYP.");
			return;
		}
		// add missing resources:
		for (cat in ["extension", "font", "object", "room", "script", "sound", "sprite", "tileset"]) {
			var cats = cat + "s";
			var catFull = Path.join([dir, cats]);
			var catNames = try {
				FileSystem.readDirectory(catFull);
			} catch (x:Dynamic) continue;
			for (rname in catNames) {
				var rdir = Path.join([catFull, rname]);
				if (!FileSystem.isDirectory(rdir)) continue;
				var rrel = '$cats\\$rname\\$rname.yy';
				if (resPathMap.exists(rrel)) continue;
				var rfull = Path.join([dir, rrel]);
				if (!FileSystem.exists(rfull)) continue;
				//
				var rd:YyBase = try {
					YYJSON.getContent(rfull);
				} catch (x:Dynamic) {
					Sys.println('`$rrel` is malformed ($x)');
					continue;
				};
				//
				var rk = rd.id;
				if (resourceMap.exists(rk)) continue;
				var rp:YyProjectResource = {
					Key: rk,
					Value: {
						id: new YyGUID(),
						resourcePath: rrel,
						resourceType: rd.modelName,
					},
				};
				//
				var rx = new YyResourceExt(rk, rp.Value);
				addResource(rx);
				addToYYP(rp);
				Sys.println('Added $cat `$rname` ($rk) back to YYP.');
			}
		}
		//
		var rootByType:Map<String, YyViewExt> = new Map();
		for (id in rootView.view.children) {
			var vx = viewMap[id];
			if (vx == null) continue;
			rootByType[vx.view.filterType] = vx;
		}
		//
		var chain:Array<String> = [];
		function setParentRec(vx:YyViewExt) {
			vx.isLinked = true;
			var i = 0;
			var vc = vx.view.children;
			while (i < vc.length) {
				var id = vc[i];
				var rx = resourceMap[id];
				if (rx == null) {
					if (vx.ignore) { i++; continue; }
					vc.splice(i, 1);
					vx.changed = true;
					Sys.println('Removing missing `$id` reference from `${chain.join("/")}`');
					continue;
				}
				if (rx.parent != null) {
					vc.splice(i, 1);
					vx.changed = true;
					Sys.println('Removing missing `${rx.val.resourcePath}` from `${chain.join("/")}` since it already has a parent.');
					continue;
				}
				rx.parent = vx;
				if (Std.is(rx, YyViewExt)) {
					var vx1:YyViewExt = cast rx;
					chain.push(vx1.view.folderName);
					setParentRec(vx1);
					chain.pop();
				}
				i += 1;
			}
		}
		setParentRec(rootView);
		//
		var reunionByType:Map<String, YyViewExt> = new Map();
		function createView(id:YyGUID, name:String, type:String):YyView {
			return {
				id: id,
				modelName: "GMFolder",
				mvc: "1.1",
				name: id,
				children: [],
				filterType: type,
				folderName: name,
				isDefaultView: false,
				localisedFolderName: ""
			};
		}
		function findReunionView(type:String) {
			var rvx = reunionByType[type];
			if (rvx != null) return rvx;
			var tl = rootByType[type];
			if (tl == null) {
				var tlid = new YyGUID();
				//
				var rp:YyProjectResource = {
					Key: tlid,
					Value: {
						id: new YyGUID(),
						resourceType: "GMFolder",
						resourcePath: 'views\\$tlid.yy'
					}
				};
				addToYYP(rp);
				//
				var tlName = type.substr(2).toLowerCase() + "s";
				var tlvd = createView(tlid, tlName, type);
				tl = new YyViewExt(tlid, rp.Value, tlvd);
				tl.changed = true;
				addView(tl);
				rootView.add(tl);
				Sys.println('Created a top-level folder for `$type`');
				rootByType[type] = tl;
			}
			for (id in tl.view.children) {
				var rx = resourceMap[id];
				if (rx == null || !Std.is(rx, YyViewExt)) continue;
				var vx:YyViewExt = cast rx;
				if (vx.view.folderName != reunionFolderName) continue;
				rvx = vx;
				break;
			}
			if (rvx == null) {
				var rvid = new YyGUID();
				var rp:YyProjectResource = {
					Key: rvid,
					Value: {
						id: new YyGUID(),
						resourceType: "GMFolder",
						resourcePath: 'views\\$rvid.yy'
					}
				};
				addToYYP(rp);
				var rvd = createView(rvid, reunionFolderName, type);
				rvx = new YyViewExt(rvid, rp.Value, rvd);
				rvx.changed = true;
				addView(rvx);
				tl.add(rvx);
				Sys.println('Created a reunion folder for `$type`');
				#if cs
				// compiler bug? no new child
				trace(tl.view);
				trace(tl.view.children);
				#end
			}
			reunionByType[type] = rvx;
			return rvx;
		}
		//
		for (vx in viewList) {
			if (vx.isLinked) continue;
			var i = 0;
			var vc = vx.view.children;
			while (i < vc.length) {
				var id = vc[i];
				var rx = resourceMap[id];
				if (rx == null) {
					vc.splice(i, 1);
					vx.changed = true;
					Sys.println('Removing missing `$id` reference from `${vx.view.folderName}`');
					continue;
				}
				if (rx.parent != null) {
					vc.splice(i, 1);
					vx.changed = true;
					Sys.println('Removing missing `${rx.val.resourcePath}` from `${vx.view.folderName}` since it already has a parent.');
					continue;
				}
				rx.parent = vx;
				i += 1;
			}
		}
		//
		for (rx in resourceList) {
			if (rx.parent != null) continue;
			var vx:YyViewExt = Std.is(rx, YyViewExt) ? cast rx : null;
			if (vx != null && vx.ignore) continue;
			var vt:String = vx != null ? vx.view.filterType : rx.val.resourceType;
			var vtl = vt.substr(2).toLowerCase();
			var rvx = findReunionView(vt);
			rvx.add(rx);
			if (vx != null) {
				Sys.println('Added `${vx.view.folderName}` to $vtl reunion folder.');
			} else {
				Sys.println('Added `${rx.val.resourcePath}` to $vtl reunion folder.');
			}
		}
		//
		var changes = 0;
		for (vx in viewList) {
			if (!vx.changed) continue;
			var vrel = vx.val.resourcePath;
			YYJSON.saveContent(Path.join([dir, vrel]), vx.view);
			Sys.println('Updated `$vrel` (${vx.getChain().join("/")}).');
			changes += 1;
		}
		if (yypChanged) {
			YYJSON.saveContent(yypPath, yyp);
			Sys.println('Updated `$yypName`.');
			changes += 1;
		}
		if (changes == 0) {
			Sys.println('Didn\'t find any problems with `$yypName`!');
		} else {
			Sys.println("All good!");
		}
	}
	static function gets() {
		#if cs
		return cs.system.Console.ReadLine();
		#else
		return Sys.stdin().readLine();
		#end
	}
	static function getc():Int {
		#if cs
		return cs.system.Console.ReadKey().KeyChar;
		#else
		return Sys.getChar(false);
		#end
	}
	static function main() {
		var yypPath = Sys.args()[0];
		if (yypPath == null) {
			var nearby = FileSystem.readDirectory(Path.directory(Sys.programPath()));
			nearby = nearby.filter(function(rel) {
				return Path.extension(rel).toLowerCase() == "yyp";
			});
			if (nearby.length > 1) {
				Sys.println("It would appear like there are multiple YYPs here, which one is real?");
				for (i in 0 ... nearby.length) {
					Sys.println(String.fromCharCode("1".code + i) + " - " + nearby[i]);
				}
				yypPath = nearby[getc() - "1".code];
			} else yypPath = nearby[0];
		}
		if (yypPath == null) {
			Sys.println("Hello! Welcome to YY-Reunion.");
			Sys.println("You can use the tool in multiple ways:");
			Sys.println("- Drag and drop your YYP onto YY-Reunion executable");
			Sys.println("- Give your YYP path via CLI (`YY-Reunion .../some/.yyp`)");
			Sys.println("- Place YY-Reunion executable in the project directory and run it from there");
			Sys.println("- Enter/paste your YYP path below");
			Sys.println("Don't forget to make a backup!");
			Sys.print("YYP path?: ");
			yypPath = gets();
		}
		if (!FileSystem.exists(yypPath)) {
			Sys.println('`$yypPath` doesn\'t seem to exist.');
		} else try {
			impl(yypPath);
		} catch (x:Dynamic) {
			Sys.println("An error occurred!");
			Sys.println(x);
			Sys.println(CallStack.toString(CallStack.exceptionStack()));
		}
		Sys.println("Press any key to exit!");
		getc();
	}
}
class YyResourceExt {
	public var parent:YyViewExt = null;
	public var key:YyGUID;
	public var val:YyProjectResourceValue;
	public function new(k:YyGUID, v:YyProjectResourceValue) {
		key = k;
		val = v;
	}
	private var getName_cache:String = null;
	public function getName():String {
		if (getName_cache == null) {
			getName_cache = Path.withoutExtension(Path.withoutDirectory(val.resourcePath));
		}
		return getName_cache;
	}
	public function getChain():Array<String> {
		var c = [getName()];
		var v = parent;
		var z = 0;
		while (v != null) {
			if (v.view.isDefaultView) break;
			c.unshift(v.view.folderName);
			v = v.parent;
			if (++z > 32) break;
		}
		return c;
	}
}
class YyViewExt extends YyResourceExt {
	public var view:YyView;
	public var changed:Bool = false;
	public var ignore:Bool;
	public var isLinked:Bool = false;
	public function new(k:YyGUID, v:YyProjectResourceValue, view:YyView) {
		super(k, v);
		this.view = view;
		ignore = view.filterType == "GMOptions" || view.isDefaultView;
	}
	
	override public function getName():String {
		return view.folderName;
	}
	
	public function add(item:YyResourceExt) {
		item.parent = this;
		view.children.push(item.key);
		changed = true;
	}
}