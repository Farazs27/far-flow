#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;
my $framework = shift @ARGV or die "Missing local media framework\n";
my $handle = DynaLoader::dl_load_file("$framework/FarFlowMediaBridge", 0) or die "Cannot load local media framework\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "FarFlowMediaRun") or die "Missing media entry point\n";
DynaLoader::dl_install_xsub("FarFlowMedia::run", $symbol);
FarFlowMedia::run();
