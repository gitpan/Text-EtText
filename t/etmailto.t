#!/usr/bin/perl -w

use lib '.'; use lib 't';
use EtTest; ettext_t_init("etmailto");
use Test; BEGIN { plan tests => 7 };

# ---------------------------------------------------------------------------

%patterns = (

 q{mailto links: <a
href="mailto:jm@nospam-jmason.org">mailto:jm@nospam-jmason.org</a> ,
mailto followed by a non-mail char: <a
href="mailto:jm@nospam-jmason.org,">mailto:jm@nospam-jmason.org,</a> and
bare email addresses: <a
href="mailto:jm@nospam-jmason.org">jm@nospam-jmason.org</a>.}, 'first',

q{ <p> <a href="mailto:test@test.org">test@test.org</a> <a
href="mailto:test@test.org">test@test.org</a> <a
href="mailto:test@test.org">mailto:test@test.org</a> }, 'second',

q{<a href=mailto:test@test.org>test@test.org</a> <a
href="mailto:test@test.org">test@test.org</a> <a
href='mailto:test@test.org'>test@test.org</a> }, 'third'

);

# ---------------------------------------------------------------------------

ok (etrun ("< data/$testname.etx", \&patterns_run_cb));
ok_all_patterns();

