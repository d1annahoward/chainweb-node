{ compiler ? "ghc901"
, rev      ? "7e9b0dff974c89e070da1ad85713ff3c20b0ca97"
, sha256   ? "1ckzhh24mgz6jd1xhfgx0i9mijk6xjqxwsshnvq789xsavrmsc36"
, pkgs     ?
    import (builtins.fetchTarball {
      url    = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
      inherit sha256; }) {
      config.allowBroken = false;
      config.allowUnfree = true;
    }
}:
let gitignoreSrc = import (pkgs.fetchFromGitHub {
      owner = "hercules-ci";
      repo = "gitignore";
      rev = "9e80c4d83026fa6548bc53b1a6fab8549a6991f6";
      sha256 = "04n9chlpbifgc5pa3zx6ff3rji9am6msrbn1z3x1iinjz2xjfp4p";
    }) {};

in
pkgs.haskell.packages.${compiler}.developPackage {
  name = "chainweb";
  root = gitignoreSrc.gitignoreSource ./.;

  overrides = self: super: with pkgs.haskell.lib; {
      ap-normalize = dontCheck super.ap-normalize;
      rosetta = self.callCabal2nix "rosetta" (pkgs.fetchFromGitHub {
        owner = "kadena-io";
        repo = "rosetta";
        rev = "5db55e77e7f0ffe7670075708843fa03d179aaa5";
        sha256 = "06rgkq5qpqq0xj3mrxq4395p3jh2p34xy3a3vxz4xgjlj9fhy1ms";
      }) {};
      network = self.callHackageDirect {
        pkg = "network";
        ver = "3.1.2.2";
        sha256 = "1kqqclg48s7x4i2sfr5pvzry3jq59794zdmmydk7rr59vh1gbmh4";
       } {};
      base64-bytestring = dontBenchmark (dontCheck (self.callHackageDirect {
        pkg = "base64-bytestring";
        ver = "1.0.0.3";
        sha256 = "1wx3zdx5amjyawqlfv2i3mishvvh4pkdk9nh7y8f4d38ykri2bx0";
       } {}));
      base16-bytestring = dontBenchmark (dontCheck (self.callHackageDirect {
        pkg = "base16-bytestring";
        ver = "0.1.1.7";
        sha256 = "0sv4gvaz1hwllv7dpm8b8xkrpsi1bllgra2niiwpszpq14bzpail";
       } {}));
      configuration-tools = dontBenchmark (dontCheck (self.callHackageDirect {
        pkg = "configuration-tools";
        ver = "0.6.0";
        sha256 = "0ia2bhy35qv1xgbqrx0jalxznj8zgg97y0zkp8cnr1r3pq5adbcd";
       } {}));
      cuckoo = dontBenchmark (dontCheck (self.callHackageDirect {
        pkg = "cuckoo";
        ver = "0.3.0";
        sha256 = "172km2552ipi9fqjmd16b4jmqw5a1414976p6xf8bxc83shxp97p";
       } {}));
      hashes = dontCheck (self.callHackageDirect {
        pkg = "hashes";
        ver = "0.1.0.1";
        sha256 = "09n2k0vwwlzjy8ax5dlq3743qkcsd21gwfibqfjmqirv30lgb5b5";
      } {});
      prettyprinter = dontCheck (self.callHackageDirect {
        pkg = "prettyprinter";
        ver = "1.6.0";
        sha256 = "0f8wqaj3cv3yra938afqf62wrvq20yv9jd048miw5zrfavw824aa";
      } {});

      quickcheck-classes-base = dontCheck (self.callHackageDirect {
        pkg = "quickcheck-classes-base";
        ver = "0.6.0.0";
        sha256 = "1mmhfp95wqg6i5gzap4b4g87zgbj46nnpir56hqah97igsbvis70";
      } {});
      pact-time = dontCheck (self.callHackageDirect {
        pkg = "pact-time";
        ver = "0.2.0.0";
        sha256 = "1cfn74j6dr4279bil9k0n1wff074sdlz6g1haqyyy38wm5mdd7mr";
      } {});

      # TODO Replace with kpkgs bump after everything is ready
      pact = dontCheck (appendConfigureFlag (self.callCabal2nix "pact" (pkgs.fetchFromGitHub {
        owner = "kadena-io";
        repo = "pact";
        rev = "ef4f089d50b5f0c19b2d6aaea80e6e2dccb0f153";
        sha256 = "09z6bznyyhy53y7z31c5gkhfsj9b6wsxiyvnf8ymqx0a0inkj07n";
      }) {}) "-f-build-tool");

      ethereum = dontCheck (self.callCabal2nix "ethereum" (pkgs.fetchFromGitHub {
        owner = "kadena-io";
        repo = "kadena-ethereum-bridge";
        rev = "10f21e96af1dce4f13e261be9dfad8c28cd299f7";
        sha256 = "1vab2m67ign6x77k1sjfjmv9sbrrl5sl2pl07rw1fw8bjqnp5vqk";
      }) {});

      chainweb-storage = dontCheck (self.callCabal2nix "chainweb-storage" (pkgs.fetchFromGitHub {
        owner = "kadena-io";
        repo = "chainweb-storage";
        rev = "07e7eb7596c7105aee42dbdb6edd10e3f23c0d7e";
        sha256 = "0piqlj9i858vmvmiis9i8k6cz7fh78zfaj47fsq5cs9v7zpj234z";
      }) {});
      nothunks = dontCheck (self.callHackageDirect {
        pkg = "nothunks";
        ver = "0.1.2";
        sha256 = "1xj5xvy3x3vixkj84cwsjl3m06z2zfszbcpxbz1j1ca83ha2gb7i";
      } {});


      fast-logger = self.callHackageDirect {
        pkg = "fast-logger";
        ver = "2.4.17";
        sha256 = "1whnbdzcfng6zknsvwgk4cxhjdvwak7yxwykwkh2mlv9ykz8b6iw";
      } {};

      wai-logger = self.callHackageDirect {
        pkg = "wai-logger";
        ver = "2.3.5";
        sha256 = "1iv6q7kpa9irjyjv9238pfqqzn7w92ccich5h8xbmv3r8qxwmvld";
      } {};

      http2 = self.callHackageDirect {
        pkg = "http2";
        ver = "2.0.3";
        sha256 = "14bqmxla0id956y37fpfx9v6crwxphbfxkl8v8annrs8ngfbhbr7";
      } {};


      wai = dontCheck (self.callHackageDirect {
        pkg = "wai";
        ver = "3.2.2.1";
        sha256 = "0msyixvsk37qsdn3idqxb4sab7bw4v9657nl4xzrwjdkihy411jf";
      } {});

      wai-cors = dontCheck (self.callHackageDirect {
        pkg = "wai-cors";
        ver = "0.2.7";
        sha256 = "10yhjjkzp0ichf9ijiadliafriwh96f194c2g02anvz451capm6i";
      } {});

      wai-middleware-throttle = dontCheck (self.callHackageDirect {
        pkg = "wai-middleware-throttle";
        ver = "0.3.0.1";
        sha256 = "13pz31pl7bk51brc88jp0gffjx80w35kzzrv248w27d7dc8xc63x";
      } {});

      wai-extra = self.callHackageDirect {
        pkg = "wai-extra";
        ver = "3.0.28";
        sha256 = "1k470vbn2c852syj15m9xzfjnaraw6cyn35ajf2b67i01ghkshgw";
      } {};

      wai-app-static = doJailbreak (dontCheck (self.callHackageDirect {
        pkg = "wai-app-static";
        ver = "3.1.7.2";
        sha256 = "184ql2k7b5i0y3b34kpcv0mxvzbhd1z5wa277z3nd67v48slax7a";
      } {}));

      warp = dontCheck (self.callHackageDirect {
        pkg = "warp";
        ver = "3.3.6";
        sha256 = "044w7ajkqlwnrpzc4zaqy284ac9wsklyby946jgfpqyjbj87985x";
      } {});

      warp-tls = self.callHackageDirect {
        pkg = "warp-tls";
        ver = "3.2.10";
        sha256 = "1zgr83zkb3q4qa03msfnncwxkmvk63gd8sqkbbd1cwhvjragn4mz";
      } {};

      cryptohash-md5 = self.callHackageDirect {
        pkg = "cryptohash-md5";
        ver = "0.11.101.0";
        sha256 = "0y38ybbd67864nw9p326a7bi7ss8b9y1vi88702y8h07zvyi2d84";
      } {};

      token-bucket = doJailbreak super.token-bucket;

      cryptohash-sha1 = doJailbreak super.cryptohash-sha1;

      hashable = doJailbreak super.hashable;

      ixset-typed = doJailbreak super.ixset-typed;

      # generic-lens-core = self.callHackageDirect {
      #   pkg = "generic-lens-core";
      #   ver = "2.2.0.0";
      #   sha256 = "0y3ncd8zxx9v4nmfpj90xrk9yygcxr95f4p2rdq46dq20rgnxgch";
      # } {};

      memory = self.callHackageDirect {
        pkg = "memory";
        ver = "0.16.0";
        sha256 = "0ix5zdq3c51k959y2n4dfka4dnfjp710c6bms0pk3vhzhxl3q1nh";
      } {} ;

      tasty-json = doJailbreak super.tasty-json;

      strict-tuple = doJailbreak super.strict-tuple;

      uuid = self.callHackageDirect {
        pkg = "uuid";
        ver = "1.3.10";
        sha256 = "0aah52jr0khq1xcx1sykwfrinfcxkl3dblvsd7h27c4h4y2gw1xa";
      } {};

      integer-gmp = doJailbreak super.integer-gmp_1_0_3_0;

      generic-lens = doJailbreak super.generic-lens;

      ghc-prim = self.callHackageDirect {
        pkg = "ghc-prim";
        ver = "0.7.0";
        sha256 = "17249709gmmp2mjscb8hh08kqazm06gsjg8ac3p45c69sv1ghlh4";
      } {};


  };
  source-overrides = {
    # Use a specific hackage version using callHackage. Only works if the
    # version you want is in the version of all-cabal-hashes that you have.
    # bytestring = "0.10.8.1";
    #
    # Use a particular commit from github
    # parsec = pkgs.fetchFromGitHub
    #   { owner = "hvr";
    #     repo = "parsec";
    #     rev = "c22d391c046ef075a6c771d05c612505ec2cd0c3";
    #     sha256 = "0phar79fky4yzv4hq28py18i4iw779gp5n327xx76mrj7yj87id3";
    #   };
  };
  modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
    buildTools = (attrs.buildTools or []) ++ [
      pkgs.zlib
      pkgs.haskell.packages.${compiler}.cabal-install
      pkgs.haskell.packages.${compiler}.ghcid
    ];
  });
}