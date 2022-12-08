(
var folder = thisProcess.nowExecutingPath.dirname;
var files = Dictionary.new;
var movements = Dictionary.new;
var master_cues;
var csv_data = CSVFileReader.read(folder+/+"data.tsv",delimiter:$\t,skipEmptyLines:true);

var max_speakers = 124;

var cue_loudnesses = Object.readArchive(folder+/+"cue-vols.scarchive");

SelectFiles(folder).do{
	arg fullpath, i;
	var pn = PathName(fullpath);
	var filename = pn.fileName;
	// "%:\t%\t%".format(i,filename,fullpath).postln;
	files[filename] = fullpath;
};

csv_data[1..].do{
	arg line, line_counter;
	var line_dict = Dictionary.new;
	line.do{
		arg item, i;
		line_dict[csv_data[0][i]] = item;
	};

	/*	line_counter.postln;
	line.postln;*/

	line_dict["movement"] = line_dict["movement"].asInteger;
	line_dict["cue"] = line_dict["cue"].asInteger;
	line_dict["speakers"] = ("[" ++ line_dict["speakers"] ++ "]").interpret;
	line_dict["loudness"] = line_dict["loudness"] !? (_.asInteger) ?? 0;

	files[line_dict["file"]] ?? {"File not found: %".format(line_dict["file"]).error};

	if(movements[line_dict["movement"]].isNil){
		movements[line_dict["movement"]] = Dictionary.new;
	};

	if(movements[line_dict["movement"]][line_dict["cue"]].isNil){
		movements[line_dict["movement"]][line_dict["cue"]] = Dictionary.newFrom(["files",List.new]);
	};

	files[line_dict["file"]] !? {
		movements[line_dict["movement"]][line_dict["cue"]]["files"].add(line_dict);
	};

	movements[line_dict["movement"]][line_dict["cue"]]["movement"] = line_dict["movement"];
	movements[line_dict["movement"]][line_dict["cue"]]["cue"] = line_dict["cue"];
};

master_cues = List.new;

movements.keys.asArray.sort.do{
	arg mvt;
	// "movement: %".format(mvt).postln;
	movements[mvt].keys.asArray.sort.do{
		arg cue;
		var cue_loudness = 0;

		if(cue_loudnesses[mvt].notNil){
			if(cue_loudnesses[mvt][cue].notNil){
				cue_loudness = cue_loudnesses[mvt][cue];
			};
		};
		// "\tcue: %".format(cue).postln;
		/*movements[mvt][cue]["files"].do{
		arg file;
		"\t\t%\t%\t%".format(file["file"],file["loudness"],file["speakers"]).postln;
		};*/

		movements[mvt][cue]["cue-loudness"] = cue_loudness;

		master_cues.add(movements[mvt][cue]);
	};
};

s.options.numOutputBusChannels_(max_speakers);
s.options.sampleRate_(48000);
s.options.numWireBufs_(512);
s.options.device_("AggregateFocusRite+Dante");
s.waitForBoot{
	var play_cue, win, scroll_view, up_next_buttons, up_next = 0, set_up_next, scroll_width, display_cue, cue_displays, group, master_vol_bus, save_cue_vols, master_vol_sl, play_and_advance_cue, spacebar_is_up = true;

	Buffer.freeAll;
	Window.closeAll;
	s.freeAll;

	master_vol_bus = Bus.control(s).set(0);

	s.sync;

	group = Group.new;

	// load all buffers
	master_cues.do{
		arg cue_dict, i;
		"Cue %".format(i).postln;
		cue_dict["files"].do{
			arg file_dict;
			var full_path = files[file_dict["file"]];
			// "\tloading: %".format(full_path).postln;
			file_dict["buffer"] = Buffer.read(s,full_path);
		};
	};

	s.sync;

	"done reading buffers".postln;

	play_cue = {
		arg index;
		var cue_dict = master_cues[index];
		"movement: %".format(cue_dict["movement"]).postln;
		"cue:      %".format(cue_dict["cue"]).postln;
		"files:".postln;
		{
			arg gate = 1;
			var env = EnvGen.kr(Env.asr(0,1,0.03),gate,doneAction:2);
			cue_dict["files"].do{
				arg file_dict;
				var buf = file_dict["buffer"];
				var nChannels = buf.numChannels;
				var sig = PlayBuf.ar(nChannels,buf,BufRateScale.ir(buf),doneAction:2);

				// mix down
				sig = Mix(sig) / nChannels;

				// loudness adjustment
				sig = sig * file_dict["loudness"].dbamp;
				sig = sig * In.kr(cue_dict["vol-bus"]).dbamp;
				sig = sig * env;
				sig = sig * In.kr(master_vol_bus).dbamp;

				"\t%\tloudness %\tto speakers: ".format(file_dict["file"],file_dict["loudness"]).post;
				file_dict["speakers"].do{
					arg spk;
					"% ".format(spk).post;
					Out.ar((spk - 1)% max_speakers,sig);
				};
				"".postln;
			};
			"".postln;
			nil;
		}.play(group);

		display_cue.(1,cue_dict);
	};

	win = Window("Blake",Rect(0,0,1000,800),false);

	scroll_width = 500;
	scroll_view = ScrollView(win,Rect(0,0,scroll_width,800));

	up_next_buttons = Array.newClear(master_cues.size);

	set_up_next = {
		arg int;
		up_next = int;
		up_next_buttons.do{
			arg but, i;
			if(up_next == i){
				but.states_([["Up Next",Color.black,Color.green]])
			}{
				but.states_([["Up Next",Color.black,Color.gray]])
			};
		};

		display_cue.(0,master_cues[up_next]);
	};

	master_cues.do{
		arg cue_dict, master_counter;
		var height = 20;
		var label_width = 120;
		var button_width = 80;
		var sl_width = 200;
		var y = height * master_counter;

		cue_dict["vol-bus"] = Bus.control(s).set(cue_dict["cue-loudness"]);

		StaticText(scroll_view,Rect(0,y,label_width,height)).string_("Mvt: % Cue: %".format(cue_dict["movement"],cue_dict["cue"]));
		Button(scroll_view,Rect(label_width,y,button_width,height))
		.states_([["Play"]])
		.canFocus_(false)
		.action_{
			play_cue.(master_counter)
		};

		up_next_buttons[master_counter] = Button(scroll_view,Rect(label_width + button_width,y,button_width,height))
		.canFocus_(false)
		.action_({
			set_up_next.(master_counter);
		});

		cue_dict["volume-slider"] = EZSlider(scroll_view,Rect(label_width + (button_width*2),y,sl_width,20),"Vol",ControlSpec(-130,24),{
			arg sl;
			cue_dict["vol-bus"].set(sl.value);
		},initVal:cue_dict["cue-loudness"],layout:'horz',labelWidth:40);
	};

	Button(win,Rect(scroll_width,(win.bounds.height/2) - 30,win.bounds.width-(scroll_width+60),60))
	.states_([["Play Next",Color.black,Color.green]])
	.canFocus_(false)
	.action_{
		play_and_advance_cue.value;
	};

	play_and_advance_cue = {
		play_cue.(up_next);
		set_up_next.(up_next+1);
	};

	StaticText(win,Rect(scroll_width,0,win.bounds.width-scroll_width,40)).string_("Up Next:");
	StaticText(win,Rect(scroll_width,win.bounds.height/2 + 30,win.bounds.width-scroll_width,40)).string_("Current:");

	cue_displays = [20,win.bounds.height/2 + 50].collect{
		arg y, i;
		var col = [Color.gray,Color.black][i];
		StaticText(win,Rect(scroll_width,y,win.bounds.width-scroll_width,100))
		.stringColor_(col);
	};

	display_cue = {
		arg pos, cue_dict;
		var string = "Movement: %\nCue: %\nNotes: ".format(cue_dict["movement"],cue_dict["cue"]);

		cue_dict["files"].do{
			arg file_dict;
			string = string + file_dict["notes"];
		};

		cue_displays[pos].string_(string);
	};

	Button(win,Rect(win.bounds.width-160,win.bounds.height-20,100,20))
	.states_([["Stop All",Color.black,Color.red]])
	.canFocus_(false)
	.action_{
		group.set(\gate,0);
	};

	Button(win,Rect(win.bounds.width-260,win.bounds.height-20,100,20))
	.states_([["Save Cue Vols"]])
	.canFocus_(false)
	.action_{
		save_cue_vols.value;
	};

	save_cue_vols = {
		var saver = Dictionary.new;
		master_cues.do{
			arg cue_dict;
			if(saver[cue_dict["movement"]].isNil){
				saver[cue_dict["movement"]] = Dictionary.new;
			};

			saver[cue_dict["movement"]][cue_dict["cue"]] = cue_dict["volume-slider"].value;
		};

		saver.writeArchive(folder+/+"cue-vols.scarchive");
	};

	master_vol_sl = EZSlider(win,Rect(win.bounds.width-60,0,60,win.bounds.height),"Master",ControlSpec(-20,20),{
		arg sl;
		master_vol_bus.set(sl.value);
	},0,layout:'vert');

	MIDIIn.connectAll;

	// nanoKontrol2 slider 8
	MIDIFunc.cc({
		arg val;
		fork({
			master_vol_sl.valueAction_(master_vol_sl.controlSpec.map(val/127));
		},AppClock);
	},7);

	win.view.keyDownAction_({
		arg view, char, modifiers, unicode, keycode, key;
		// [view, char, modifiers, unicode, keycode, key].postln;
		if(spacebar_is_up.and(unicode == 32)){
			play_and_advance_cue.value;
		};

		spacebar_is_up = false;
	})
	.keyUpAction_({
		arg view, char, modifiers, unicode, keycode, key;

		if(unicode == 32){
			spacebar_is_up = true;
		}
	});

	set_up_next.(0);

	win.front;
};
nil;
)