# common functionality for tests.
# imported into main for ease of use.

package main;

use Cwd;
use File::Path;

# Set up for testing. Exports (as global vars):
# out: $home: $HOME env variable
# out: $cwd: here
# out: $scr: ettext2html script
#
sub ettext_t_init {
  my $tname = shift;

  $cwd = getcwd;

  $scr = $ENV{'SCRIPT'};
  $scr ||= "../ettext2html";

  (-f "t/test_dir") && chdir("t");        # run from ..
  rmtree ("log");
  mkdir ("log", 0755);

  $home = $ENV{'HOME'};
  $home ||= $ENV{'WINDIR'} if (defined $ENV{'WINDIR'});

  $ENV{'TEST_DIR'} = $cwd;
  $testname = $tname;
}

sub ettext_t_finish {
  # no-op currently
}

# Run ettext. Calls back with the output.
# in $args: arguments to run with
# in $read_sub: callback for the output (should read from <IN>).
# This is called with no args.
#
# out: $ettext_exitcode global: exitcode from sitescooper
# ret: undef if sitescooper fails, 1 for exit 0
#
sub etrun {
  my $args = shift;
  my $read_sub = shift;

  rmtree ("log/outputdir.tmp"); # some tests use this
  mkdir ("log/outputdir.tmp", 0755);

  if (defined $ENV{'ETTEXT2HTML_ARGS'}) {
    $args = $ENV{'ETTEXT2HTML_ARGS'} . " ". $args;
  }

  # added fix for Windows tests from Rudif
  my $scrargs = "$scr $args > log/$testname.html";
  $scrargs =~ s!/!\\!g if ($^O =~ /^MS(DOS|Win)/i);
  print ("\t$scrargs\n");
  system ("$scrargs");
  $ettext_exitcode = ($?>>8);
  if ($ettext_exitcode != 0) { return undef; }
  &checkfile ("$testname.html", $read_sub);
  1;
}

# ---------------------------------------------------------------------------

sub checkfile {
  my $filename = shift;
  my $read_sub = shift;

  # print "Checking $filename\n";
  if (!open (IN, "< log/$filename")) {
    warn "cannot open log/$filename"; return undef;
  }
  &$read_sub();
  close IN;
}

# ---------------------------------------------------------------------------

sub pattern_to_re {
  my $pat = shift;
  $pat = quotemeta($pat);

  # make whitespace irrelevant; match any amount as long as the
  # non-whitespace chars are OK.
  $pat =~ s/\\\s/\\s\*/gs;
  $pat;
}

# ---------------------------------------------------------------------------

sub patterns_run_cb {
  local ($_);
  $_ = join ('', <IN>);

  foreach my $pat (sort keys %patterns) {
    my $safe = pattern_to_re ($pat);
    # print "JMD $patterns{$pat}\n";
    if ($_ =~ /${safe}/s) {
      $found{$patterns{$pat}}++;
    }
  }
  foreach my $pat (sort keys %anti_patterns) {
    my $safe = pattern_to_re ($pat);
    #print "JMD $patterns{$pat}\n";
    if ($_ =~ /${safe}/s) {
      $found_anti{$patterns{$pat}}++;
    }
  }
}

sub ok_all_patterns {
  foreach my $pat (sort keys %patterns) {
    my $type = $patterns{$pat};
    print "\tChecking $type\n";
    if (ok (defined $found{$type})) {
      ok ($found{$type} == 1) or warn "Found more than once: $type\n";
    } else {
      warn "\tNot found: $type = $pat\n";
      ok (0);                     # keep the right # of tests
    }
  }
  foreach my $pat (sort keys %anti_patterns) {
    my $type = $anti_patterns{$pat};
    print "\tChecking for anti-pattern $type\n";
    if (!ok (!defined $found{$type})) {
      warn "\tFound anti-pattern: $type = $pat\n";
    }
  }
}

sub clear_pattern_counters {
  %found = ();
  %found_anti = ();
}

1;
