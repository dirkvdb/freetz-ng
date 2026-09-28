{ lib, pkgs, ... }:

let
  ecjVersion = "3.46.100";

  # Debian and Ubuntu provide this command in their `ecj` package.  Nixpkgs
  # does not currently package the standalone Eclipse compiler, so keep the
  # small wrapper here and pin the upstream jar by hash.
  ecj = pkgs.stdenvNoCC.mkDerivation {
    pname = "ecj";
    version = ecjVersion;

    src = pkgs.fetchurl {
      url = "https://repo.maven.apache.org/maven2/org/eclipse/jdt/ecj/${ecjVersion}/ecj-${ecjVersion}.jar";
      hash = "sha256-dMkxckdf7gzU5u77RCM1Ft1AUlZC2jXQCRRtl+pZgik=";
    };

    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      install -Dm644 "$src" "$out/share/java/ecj.jar"
      makeWrapper ${pkgs.jdk21_headless}/bin/java "$out/bin/ecj" \
        --add-flags "-jar $out/share/java/ecj.jar"
      runHook postInstall
    '';
  };

  perlWithCRC32 = pkgs.perl.withPackages (perlPackages: [
    perlPackages.StringCRC32
  ]);

  # Freetz compares `gcc -dumpversion` with `test -ge`, which cannot parse the
  # full version (for example 15.2.0) returned by Nixpkgs' GCC. Preserve the
  # real compiler behavior except for that one legacy query.
  gccForFreetz = pkgs.symlinkJoin {
    name = "gcc-for-freetz-${pkgs.gcc_multi.version}";
    paths = [
      (pkgs.writeShellScriptBin "gcc" ''
        if [[ "$#" -eq 1 && "$1" == "-dumpversion" ]]; then
          printf '%s\n' ${lib.escapeShellArg (lib.versions.major pkgs.gcc_multi.version)}
          exit 0
        fi
        exec ${pkgs.gcc_multi}/bin/gcc "$@"
      '')
      (pkgs.writeShellScriptBin "cc" ''
        if [[ "$#" -eq 1 && "$1" == "-dumpversion" ]]; then
          printf '%s\n' ${lib.escapeShellArg (lib.versions.major pkgs.gcc_multi.version)}
          exit 0
        fi
        exec ${pkgs.gcc_multi}/bin/gcc "$@"
      '')
      (pkgs.writeShellScriptBin "g++" ''
        exec ${pkgs.gcc_multi}/bin/g++ "$@"
      '')
      (pkgs.writeShellScriptBin "c++" ''
        exec ${pkgs.gcc_multi}/bin/g++ "$@"
      '')
    ];
  };

  toolPackages = with pkgs; [
    # Build and source-control tools.
     autoconf
     automake
     bc
    binutils
    bison
    bzip2
    ccache
    cmake
    cpio
    curl
    diffutils
    dos2unix
    file
    findutils
    flex
    gawk
    gccForFreetz
    gettext
    git
    gnumake
    gnugrep
    gnused
    gnutar
    intltool
    libtool
    m4
    patch
    patchutils
    pkg-config
    rpcsvc-proto
    rsync
    subversion
    texinfo

    # Archive, download and utility programs used by the build recipes.
    coreutils
    kmod
    ncftp
    netcat
    nettools
    pv
    sharutils
    unar
    unzip
    util-linux
    wget
    which
    xz
    zip

    # Image/tagging tools listed by the supported distributions.
    graphicsmagick
    imagemagick
    inkscape

    jdk21_headless
  ];

  hostLibraries = with pkgs; [
    acl
    attr
    glib
    gnutls
    libcap
    libelf
    libusb-compat-0_1
    libuuid
    libxml2
    ncurses5
    openssl
    readline
    sqlite
    zlib
    zstd
  ];

  allPackages =
    toolPackages
    ++ hostLibraries
    ++ [
      ecj
      perlWithCRC32
    ];

  # Freetz assumes an FHS layout, including /usr/bin/perl shebangs. All make
  # processes run in this bubblewrap-based FHS view; the checkout itself stays
  # mounted at its normal path and is not patched.
  freetzFhs = pkgs.buildFHSEnv {
    name = "freetz-fhs";
    targetPkgs = _: allPackages;
    multiArch = true;
    multiPkgs =
      packages: with packages; [
        ncurses5
        zlib
      ];
    extraOutputsToInstall = [ "dev" ];
    runScript = "bash";
    profile = ''
      export CC=gcc
      export CXX=g++
      # Freetz supplies its own target and host-tool flags. Nix's compiler
      # wrapper otherwise injects -Werror=format-security and other flags that
      # break supported upstream sources such as BusyBox host tools.
      export NIX_HARDENING_ENABLE=

      # Once bootstrapped, Freetz puts its own Autotools and libtool ahead of
      # the host tools.  buildFHSEnv's global macro path would still make that
      # aclocal import Nixpkgs' libtool macros, mixing (for example) 2.5.4
      # macros with Freetz's 2.6.2 libtool and breaking generated builds.
      unset ACLOCAL_PATH

      # The surrounding development container maps only the invoking UID.
      # In such a user namespace, a real chown(2) to uid/gid 0 fails with
      # EINVAL. Freetz's fakeroot supports suppressing that unnecessary real
      # syscall while still recording and reporting the emulated ownership.
      export FAKEROOTDONTTRYCHOWN=1
    '';
  };

  # This takes precedence over gnumake in the devenv profile and enters the
  # FHS view before invoking the real make executable.
  freetzMake =
    (pkgs.writeShellScriptBin "make" ''
      exec ${freetzFhs}/bin/freetz-fhs \
        -c 'exec /usr/bin/make "$@"' -- "$@"
    '').overrideAttrs
      (old: {
        meta = (old.meta or { }) // {
          priority = 1;
        };
      });
in
{
  packages =
    assert lib.assertMsg pkgs.stdenv.hostPlatform.isLinux
      "Freetz-NG firmware can only be built on Linux";
    assert lib.assertMsg pkgs.stdenv.hostPlatform.isx86_64
      "Freetz-NG's 32-bit host tools require an x86_64 Linux host";
    [ freetzMake ] ++ allPackages;

  # Do not let a user's compiler selection accidentally bypass gcc_multi.
  env.CC = "gcc";
  env.CXX = "g++";

  scripts.freetz-shell.exec = ''
    exec ${freetzFhs}/bin/freetz-fhs "$@"
  '';

  scripts.freetz-check.exec = ''
    set -euo pipefail

    required_commands=(
      autoconf automake autopoint bc bison bunzip2 bzip2 ccache cmake cpio
      curl ecj file filterdiff find flex g++ gawk gcc gettext git
      glib-genmarshal gm hexdump identify inkscape intltoolize ldconfig
      libtool libtoolize lsdiff make md5sum mktemp nc ncftp patch perl
      pkg-config pv readlink realpath rpcgen rsync sed sha256sum sort svn
      tar unar uudecode unzip unxz wget xz zip
    )

    missing=0
    for command_name in "''${required_commands[@]}"; do
      if ! command -v "$command_name" >/dev/null; then
        printf 'missing command: %s\n' "$command_name" >&2
        missing=1
      fi
    done
    (( missing == 0 )) || exit 1

    work_dir="$(mktemp -d)"
    trap 'rm -rf -- "$work_dir"' EXIT

    cat >"$work_dir/headers.c" <<'EOF'
    #include <acl/libacl.h>
    #include <glib.h>
    #include <gnutls/gnutls.h>
    #include <libelf.h>
    #include <libxml/parser.h>
    #include <ncurses.h>
    #include <openssl/ssl.h>
    #include <readline/readline.h>
    #include <sqlite3.h>
    #include <sys/capability.h>
    #include <usb.h>
    #include <uuid/uuid.h>
    #include <zlib.h>
    #include <zstd.h>
    int main(void) { return 0; }
    EOF

    gcc \
      $(pkg-config --cflags glib-2.0 gnutls libxml-2.0 ncurses openssl \
        readline sqlite3 zlib libzstd) \
      -c "$work_dir/headers.c" -o "$work_dir/headers.o"

    if ! printf 'int main(void) { return 0; }\n' \
      | gcc -m32 -x c - -latomic -o "$work_dir/hello32" \
        2>"$work_dir/gcc32.log"; then
      cat "$work_dir/gcc32.log" >&2
      exit 1
    fi
    "$work_dir/hello32"

    perl -MString::CRC32 -e 1
    ecj -version >/dev/null

    ${freetzFhs}/bin/freetz-fhs -c '
      test -x /bin/bash
      test -x /usr/bin/env
      test -x /usr/bin/perl
      test -f /usr/include/ncurses.h
      test -f /usr/include/zlib.h
      /usr/bin/perl -MString::CRC32 -e 1
    '

    printf 'Freetz build prerequisites are available (including multilib).\n'
  '';

  enterShell = ''
    set -euo pipefail

    secretspec run -- bash -euc '
      umask 077
      passwd_file=make/pkgs/mosquitto/files/root/etc/default.mosquitto/passwd
      tmp_dir="$(mktemp -d "''${passwd_file}.XXXXXX")"
      tmp_file="''${tmp_dir}/passwd"
      cleanup() { rm -rf -- "$tmp_dir"; }
      trap cleanup EXIT

      ${pkgs.mosquitto}/bin/mosquitto_passwd \
        -b -c "$tmp_file" "$MQTT_USERNAME" "$MQTT_PASSWORD"
      mv -f -- "$tmp_file" "$passwd_file"
      trap - EXIT
      rmdir -- "$tmp_dir"
    '

    echo "Freetz-NG build environment"
    echo "Run 'freetz-check' to verify all host prerequisites."
  '';
}
