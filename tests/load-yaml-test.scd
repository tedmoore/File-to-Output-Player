(
var thisFolder = thisProcess.nowExecutingPath.dirname;
d = "test.yaml".resolveRelative.parseYAMLFile;
d["cues"].do{
	arg cue;
	var cue_loudness = cue["loudness"];
	var cue_folder = cue["folder"];

	"cue %".format(cue_folder).postln;
	cue["soundfiles"].keysValuesDo{
		arg name, data;
		var filepath = thisFolder+/+"cues/%/%".format(cue_folder,name);

		name.postln;
		filepath.postln;
		File.exists(filepath).postln;
		data.postln;
		"".postln;
	};
};
nil;
)