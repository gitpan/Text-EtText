#!/usr/bin/perl -w

use lib '.'; use lib 't';
use EtTest; ettext_t_init("etlists");
use Test; BEGIN { plan tests => 21 };

# ---------------------------------------------------------------------------

%patterns = (

  q{Checking lists with no start-end tags. 
  </p> <ul> <li> <p> list 1 </p> </li> <li> <p> l1 i2 </p> </li>
  <li> <p> l1 i3 </p> </li> </ul> <p> Next! I prefer this one I think. },
  'simple_ul',

  q{Next! I prefer this one I think.  </p> <ol> <li> <p> foo </p> </li>
  <li> <p> bar </p> </li> <li> <p> baz </p> </li> </ol> <p>
  How about definition lists? },
  'simple_ol',

  q{How about definition lists?  </p> <dl> <dt> Foo </dt> <dd> <p> a random term 
   </p> </dd> <dt> Bar </dt> <dd> <p> yet another </p> </dd> <dt> Baz </dt>
   <dd> <p> you get the idea.  </p> </dd> </dl> <p> That},
  'defn_list',

  q{Checking lists with included start-end tags.  </p>
  <ul> <li> <p> list 1 </p> </li> <li> <p> l1 i2 </p> </li> <li> <p>
  l1 i3 </p> </li> </ul> <p> Next! I prefer this one I think. },
  'included_ul',

  q{Next! I prefer this one I think.  </p> <ol> <li> <p> foo </p>
  </li> <li> <p> bar </p> </li> <li> <p> baz </p> </li> </ol> <p>
  What about indented lists? },
  'included_ol',

  q{What about indented lists?  </p> <ul> <li> <p> list 1 </p>
  </li> <li> <p> l1 i2 </p> </li> <ul> <li> <p> l2 i1 </p> </li> <li> <p>
  l2 i2 </p> </li> </ul> <li> <p> l1 i3 </p> </li> <li> <p> l1 i4 
  </p> </li> <ol> <li> <p> ol2 i1 </p> </li> <li> <p> ol2 i2 </p> </li>
  </ol> <li> <p> l1 i5 </p> </li> </ul> <p> Tricky indented list },
  '2lists_1',

  q{Tricky indented list -- it has 3 levels, and the innermost falls back
  to the outermost. Ouch.  </p>
  <ul> <li> <p> l1 i2 </p> </li> <ul> <li> <p> l2 i1 </p> </li> <li>
  <p> l2 i2 </p> </li> <ul> <li> <p> l3 i1 </p> </li> <li> <p> l3 i2 
  </p> </li> <li> <p> l3 i3 </p> </li> </ul> </ul> <li> <p> l1 i3 
  </p> </li> </ul> <p> That},
  '3lists_1',

  q{the lot then. Oh, one more -- end on an EOF.  </p> <ul><li><p>foo </p></li> </ul><p>},
  'end_on_eof',

  q{Lists where the items are right next to one another...  </p>
   <ul> <li> foo </li> <li> bar </li> <li> baz </li> <li> glorp 
   </li> <li> <p> with a paragraph break </p> </li> <li> <p> and another. 
   </p> </li> </ul>},
  'tight_lists',

  q{</ul><p>And where they look like they do on-screen in HTML:
  </p>

  <ul><li>foo2
  </li>
  <li>bar2
  </li>
  <li>baz2
  </li>
  <li>glorp2
  </li>

  <li><p>withpara 2
  </p></li>

  </ul><p>that's it.}, 'tight_lists_2',


);

# ---------------------------------------------------------------------------

ok (etrun ("< data/$testname.etx", \&patterns_run_cb));
ok_all_patterns();

