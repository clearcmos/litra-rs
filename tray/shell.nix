{ pkgs ? import <nixpkgs> {} }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    pyqt6
  ]);
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    pythonEnv
    qt6.qtwayland
  ];

  shellHook = ''
    echo "Litra Tray Development Environment"
    echo "=================================="
    echo ""
    echo "Run the application:"
    echo "  python src/litra_tray.py"
    echo ""
    echo "Build the package:"
    echo "  nix-build"
    echo ""

    # Set up Wayland support
    export QT_QPA_PLATFORM=wayland
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
  '';
}
