{
  description = "Litra Glow System Tray Control - KDE Plasma tray application for Logitech Litra lights";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Python with required dependencies
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyqt6
        ]);

        # The main application package
        litra-tray = pkgs.stdenv.mkDerivation {
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

            # Wrap the script to use our Python environment and ensure litra is in PATH
            wrapProgram $out/bin/litra-tray \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pythonEnv ]} \
              --set PYTHONPATH ${pythonEnv}/${pythonEnv.sitePackages}
          '';

          meta = with pkgs.lib; {
            description = "KDE Plasma system tray application for controlling Logitech Litra Glow lights";
            homepage = "https://github.com/yourusername/litra-tray";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "litra-tray";
          };
        };

      in
      {
        # Default package
        packages.default = litra-tray;
        packages.litra-tray = litra-tray;

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv
            qt6.qtwayland  # For Wayland support
          ];

          shellHook = ''
            echo "Litra Tray Development Environment"
            echo "=================================="
            echo ""
            echo "Available commands:"
            echo "  python src/litra_tray.py  - Run the application"
            echo "  nix build                 - Build the package"
            echo "  nix run                   - Run the built package"
            echo ""
            echo "Python packages available:"
            echo "  - PyQt6"
            echo ""

            # Set up Wayland support
            export QT_QPA_PLATFORM=wayland
            export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
          '';
        };

        # App for running directly
        apps.default = {
          type = "app";
          program = "${litra-tray}/bin/litra-tray";
        };
      }
    );
}
