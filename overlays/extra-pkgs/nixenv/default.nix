{
	stdenv
}:
let
	script = ./nixenv;
in
stdenv.mkDerivation {
	src = script;
	buildScript = ''
		runHook preBuild

		mkdir -p $out/bin
		cp nixenv $out/bin

		patchShebands $out/bin/nixenv

		runHook postBuild
	'';
}
