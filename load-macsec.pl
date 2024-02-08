#!/usr/bin/perl
package p2p::macsec::load;
use strict;
use warnings;
use v5.35;

my $MOD_URL = q{https://github.com/sombr/ansible-build-macsec-on-rpi/raw/main/macsec.ko};
my $MOD_DW_PATH = q{/root/macsec.ko};

sub test_modprobe {
    # Check if we can load the module.
    my $test_modprobe = qx{modprobe macsec 2>&1};
    my $no_macsec_module = $test_modprobe =~ m{Module macsec not found in directory}i;
    my $no_rights = $test_modprobe =~ m{Operation not permitted};

    return $no_macsec_module ? "missing" : $no_rights ? "unloaded" : "present";
}

sub test_dwl {
    my $stat = qx{sudo ls -lh $MOD_DW_PATH 2>&1};
    return "missing" if $stat =~ m{No such file or directory};

    return "incorrect" unless $stat =~ m{^-r--------\s+\d*\s+root\s+root\s+};

    return "present"
}

sub run {
    my $test_macsec = qx{ip macsec show 2>&1};

    # Check if we've having issues talking to MacSec in kernel.
    my $no_macsec_in_kernel = $test_macsec =~ m{Error talking to the kernel};
    say "Macsec is available, exiting" and exit(0) unless $no_macsec_in_kernel;

    say "No macsec available for `ip macsec` configuration";

    my $mod_state = test_modprobe();
    say "Macsec is available, exiting" and exit(0) if $mod_state eq "present";

    say "Macsec module state: $mod_state";

    if ($mod_state eq "unloaded") {
        say "Macsec module found, try modprobe with sudo";
        system(qq{sudo modprobe macsec});

        $mod_state = test_modprobe();
        say "Loaded, exiting" and exit(0) if $mod_state eq "present";
    }

    # check architecture, I only have the precompiled one for RPis
    my $uname = qx{uname -a};
    my $on_rpi = $uname =~ m{Linux.*raspi.*Ubuntu.*aarch64};

    die "Not running on a raspberrypi. No way to proceed, please compile a module yourself" unless $on_rpi;

    my $download_state = test_dwl();
    say "Download state: $download_state at path $MOD_DW_PATH";

    unless ($download_state eq "present") {
        # try loading
        say "Trying to download and load a pre-compiled module (check the repo instructions on how to build a new one).";
        system(qq{wget '$MOD_URL' -q -O /tmp/macsec.ko}) and die "cannot download";
        system(q{sudo mv /tmp/macsec.ko /root/ && sudo chmod 400 /root/macsec.ko && sudo chown root:root /root/macsec.ko}) and die "cannot adjust owner";
    }

    system(qq{modprobe /root/macsec.ko}) and die "cannot load the module";
}

__PACKAGE__->run();
