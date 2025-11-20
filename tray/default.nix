{ pkgs ? import <nixpkgs> {} }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    pyqt6
  ]);
in
pkgs.stdenv.mkDerivation {
  pname = "litra-tray";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  buildInputs = [ pythonEnv ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p $out/bin
    cp src/litra_tray.py $out/bin/litra-tray
    chmod +x $out/bin/litra-tray

    # Install desktop file
    mkdir -p $out/share/applications
    cp litra-tray.desktop $out/share/applications/

    # Wrap the script to use our Python environment
    wrapProgram $out/bin/litra-tray \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pythonEnv ]} \
      --set PYTHONPATH ${pythonEnv}/${pythonEnv.sitePackages}
  '';

  meta = with pkgs.lib; {
    description = "KDE Plasma system tray application for controlling Logitech Litra Glow lights";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "litra-tray";
  };
}
