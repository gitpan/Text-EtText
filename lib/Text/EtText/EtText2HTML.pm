#

=head1 NAME

Text::EtText::EtText2HTML - convert from the simple EtText editable-text format
into HTML

=head1 SYNOPSIS

  my $t = new Text::EtText::EtText2HTML;
  print $t->text2html ($text);

or

  my $t = new Text::EtText::EtText2HTML;
  print $t->text2html ();		# from STDIN

=head1 DESCRIPTION

ettext2html will convert a text file in the EtText editable-text format into
HTML.

For more information on the EtText format, check the WebMake documentation on
the web at http://webmake.taint.org/ .

=head1 METHODS

=over 4

=cut

package Text::EtText::EtText2HTML;

require Exporter;
use Carp;
use strict;
use locale;
use HTML::Entities;

use Text::EtText::LinkGlossary;
use Text::EtText::DefaultGlossary;

use vars qw{
	@ISA @EXPORT $VERSION $ATTRS_WITH_URLS $BALANCED_TAG_GEN_TAGS
	$URL_PROTECTOR $prot
};

@ISA = qw(Exporter);
@EXPORT = qw();

$VERSION = "1.1";
sub Version { $VERSION; }

# attributes that can take URL arguments: cf. HTML::LinkExtor.
$ATTRS_WITH_URLS =
	qr{href|src|lowsrc|usemap|action|background|codebase|code}i;

$BALANCED_TAG_GEN_TAGS =
	qr{(?:b|i|em|q|strong|h\d|code|abbr|acronym|address|big|cite|del|ins|s|small|strike|sub|sup|u|samp|kbd|var|span)}i;

$URL_PROTECTOR = '[[URL]]';

###########################################################################

=item $f = new Text::EtText::EtText2HTML

Constructs a new C<Text::EtText::EtText2HTML> object.

=cut

sub new {
  my $class = shift;
  $class = ref($class) || $class;

  my $self = {
    # in parameters:
    'def_list_style'	=> 'ul',	# default list style
    'html_block_tag'	=> 'main',	# name of the EtText block
    'glossary',		=> undef,	# global glossary of links
    'options',		=> { },		# optional EtText settings
  };

  # set defaults for the options.
  $self->{options}->{"EtTextOneCharMarkup"} = 0;
  $self->{options}->{"EtTextBaseHref"} = '';
  $self->{options}->{"EtTextHrefsRelativeToTop"} = 1;

  bless ($self, $class);
  $self;
}

###########################################################################

=item $f->set_option ($optname, $optval);

Set an EtText option.  (Options can also be set on the WebMake object itself,
or from inside the WebMake file.)  Currently supported options are:

=over 4

=item EtTextOneCharMarkup (default: 0)

Allow one-character sets of asterisks etc. to mark up as strong, emphasis etc.,
instead of the default two-character markup.

=item EtTextBaseHref (default: '')

The base HREF to use for relative links.  If set, all relative links
in tags with HREF attributes will be rewritten as absolute links,
making the output HTML independent of the URL tree structure.

=item EtTextHrefsRelativeToTop (default: 1)

Indicates that all EtText links are relative to the top of the WebMake document
tree. This (obviously) is only relevant if you are using EtText in conjunction
with WebMake.  If set, all relative links in tags with HREF attributes will be
rewritten as relative to the ''top'' of the WebMake site, making the output
HTML independent of the URL tree structure.

=back

=cut

sub set_option {
  my ($self, $optname, $optval) = @_;
  $self->{options}->{$optname} = $optval;
}

sub set_options {
  my ($self, %opts) = @_;
  my ($optname, $optval);
  while (($optname, $optval) = each %opts) {
    $self->set_option ($optname, $optval);
  }
}

###########################################################################

=item $html = $f->set_glossary ($glosobj)

Provide a glossary for shared link definitions, allowing link definitions to be
shared and reused across multiple EtText files.  C<$glosobj> must implement the
interface defined by C<Text::EtText::LinkGlossary>.

See below for more information on this interface.

=cut

sub set_glossary {
  my ($self, $glos) = @_;
  $self->{glossary} = $glos;
}

###########################################################################

=item $html = $f->text2html( [$text] )

Convert text, either from the argument or from STDIN, into HTML.

=cut

sub text2html {
  my $self = shift;
  local ($_);
  my @txt = ();
  my $html = '';
  
  $self->{links} = { };
  $self->{auto_links} = { };

  if ($#_ >= 0) {
    $html = join ('', @_);
  } else {
    while (<STDIN>) { $html .= $_; }
  }

  if (!defined $self->{glossary}) {
    $self->{glossary} = new Text::EtText::DefaultGlossary();
  }
  $self->{glossary}->open();

  my $blocktag = $self->{html_block_tag};

  # trim DOS or Mac line endings, yuck
  $html =~ s/\r\n/\n/gs;
  $html =~ s/\r/\n/gs;


  $self->do_options_and_protection (\$html);
  $self->do_text_markup (\$html);
  $self->do_ettext_links (\$html);
  $self->do_segmented_traverse(\$html);
  $self->do_entities (\$html);
  $self->do_headings (\$html);

  # if we have indented paragraphs, we need to run them through the
  # list/blockquote markup engine.
  if ($html =~ /<p>[ \t]+/) {
    $html = $self->markup_lists ($html);
  }

  $self->do_sidebars (\$html);
  $self->do_final_cleanup (\$html);

  # now reconvert the protected HTML (if any) back into
  # valid HTML.
  $self->unprotect_html (\$html);

  #$html =~ s/^\s*//gs;
  #$html =~ s/\s*$//gs;	# trim leading/trailing space
  delete $self->{links};
  delete $self->{auto_links};

  $html;
}

sub is_valid_glossary_key {
  my ($k) = @_;

  if ($k =~ /^\d+$/ || $k =~ /^.{0,2}$/) { return 0; }
  1;
}

sub do_options_and_protection {
  my ($self, $html) = @_;
  local ($_);

  # trim EtText options.
  $$html =~ s{<etoption>\s*(\S+)\s*=\s*(\S+)\s*<\/etoption>}{
    $self->{options}->{$1} = $2;
  }geis;
  $self->{options}->{"EtTextOneCharMarkup"} += 0;

  # protect text inside the editable area
  $$html =~ s{<!--etsafe-->(.*?)<!--\/etsafe-->}{
    $_ = $1; $self->protect_html(\$_);
    "<!--etsafe-->$_<!--/etsafe-->";
  }geis;
  $$html =~ s{<!--etsafe-->(.*?)<!--\/etsafe-->}{
    $_ = $1; $self->protect_html(\$_);
    "<!--etsafe-->$_<!--/etsafe-->";
  }geis;

  $$html =~ s{<xmp>(.*?)<\/xmp>}{
    $_ = $1; $self->protect_html(\$_);
    "<xmp>$_</xmp>";
  }geis;
  $$html =~ s{<pre>(.*?)<\/pre>}{
    $_ = $1; $self->protect_html(\$_);
    "<pre>$_</pre>";
  }geis;
}

sub do_text_markup {
  my ($self, $html) = @_;
  local ($_);

  # first, find all-underscore lines -- avoid <em></em><em></em>....
  # avoids an issue with Suelette Davis & Julian Assange's _Underground_
  $$html =~ s/\n\s*_{10,}\s*\n/\n<hr \/>\n\n/gs;

  # convert **foo** to <strong>foo</strong>
  $$html =~ s,\*\*(.*?)\*\*,<strong>$1</strong>,gs;
  $$html =~ s,\_\_(.*?)\_\_,<em>$1</em>,gs;
  $$html =~ s,\#\#(.*?)\#\#,<code>$1</code>,gs;

  # Caolan's patch to do one-char markup: (off by default
  # currently, set "EtTextOneCharMarkup" = 1 to turn it on)
  if ($self->{options}->{"EtTextOneCharMarkup"}) {
    $$html =~ s,(\s|[\>\<\_\']*)\*
    		([\>\<\_\']*[\>\<\_\']*.*?[\>\<\_\']*[\>\<\_\']*)
	    	\*([\>\<\_\']*|\s),$1<strong>$2</strong>$3,gsx;	#'
    $$html =~ s,(\s|[\>\<\*\']*)\_
    		([\>\<\*\']*[\>\<\*\']*.*?[\>\<\*\']*[\>\<\*\']*)
	    	\_([\>\<\*\']*|\s),$1<em>$2</em>$3,gsx;	#'
    $$html =~ s,(\s|[\>\<\*\']*)\'
    		([\>\<\*\_]*[\>\<\*\_]*.*?[\>\<\*\_]*[\>\<\*\_]*)
	    	\'([\>\<\*\_]*|\s),$1<code>$2</code>$3,gsx;	#'
  }


  # convert b{text} to <b>text</b>				#{
  1 while $$html =~ s{(${BALANCED_TAG_GEN_TAGS})\{([^\{\}]+)\}}
	{<$1>$2</$1>}gisx;

  # convert span.foo{text} to <span class="foo">text</span> etc. #{
  1 while $$html =~ s{(${BALANCED_TAG_GEN_TAGS})\.(\S+)\{([^\{\}]+)\}}
	{<$1 class="$2">$3</$1>}gisx;
}

sub do_ettext_links {
  my ($self, $html) = @_;
  local ($_);

  # link definitions.
  $$html =~ s{^\s+\[([^\]]+)\]\:\s+(\S+)\s*$}{
    $self->{links}->{$1} = $2; "\n";
  }giem;

  $$html =~ s{^\s+Auto:\s+\[([^\]]+)\]\:\s+(\S+)\s*$}{
    $self->{auto_links}->{$1} = $2; "\n";
  }giem;

  # links.
  $$html =~ s{\"([^\"]+?)\"\s*\[([^\]\s]+)\]}{	#"
    $self->link_write (1, $2, $1);
  }ges;

  $$html =~ s{\b([^>\s]+)\s*\[([^\]\s]+)\]}{
    $self->link_write (0, $2, $1);
  }ges;

  $$html =~ s{(<[^>]+>)\s*\[([^\]\s]+)\]}{
    $self->link_write (0, $2, $1);
  }ges;


  # glossary links.
  if (defined $self->{glossary}) {
    $self->update_glossary();

    $$html =~ s{((?!=).\s)\"([^\"]+?)\"}{	#"
      $1.$self->link_write (1, $2, $2);
    }geis;
  }
}

sub _handle_link_href {
  my ($base, $url) = @_;

  if ($url =~ /${URL_PROTECTOR}/) { return $url; }
  $url =~ s/^\"(.*)\"$/$1/g;
  $url =~ s/^\'(.*)\'$/$1/g;

  # first protect existing hrefs and src tags. This only operates
  # on hrefs with protocol: tags at the start.
  if ($url =~ s/^([A-Za-z0-9_-]+):/$1${URL_PROTECTOR}:/) {
    return $url;
  }

  if ($url =~ /^\$\(/) { return $url; }

  if ($url =~ /^\.{0,2}\//) { return $URL_PROTECTOR.$url; }
  if (defined $base && $base ne '') { return $URL_PROTECTOR.$base.$url; }
  $URL_PROTECTOR.$url;
}

sub update_glossary {
  my ($self) = @_;
  # if we have a glossary, add our new links to it.
  # trim out ones that are numeric only, or 1 char long.
  if (defined $self->{glossary}) {
    my ($k, $v);

    while (($k, $v) = (each %{$self->{links}})) {
      next unless is_valid_glossary_key ($k);
      $self->{glossary}->put_link ($k, $v);
    }

    my @newkeys = ();
    while (($k, $v) = (each %{$self->{auto_links}})) {
      $self->{glossary}->put_auto_link ($k, $v);
      push (@newkeys, $k);
    }
    if ($#newkeys >= 0) {
      $self->{glossary}->add_auto_link_keys (@newkeys);
    }

    $self->{glossary}->close();
  }
}

# ---------------------------------------------------------------------------

sub do_segmented_traverse {
  my ($self, $html) = @_;
  local ($_);

  my $url = undef;
  my $done = '';
  $prot = $URL_PROTECTOR;

  # De-relativise relative links.
  my $base = $self->{options}->{"EtTextBaseHref"};
  if (defined $base && $base ne '') {
    if ($base !~ /\/$/) { $base .= '/'; }
  }
  if ($self->{options}->{"EtTextHrefsRelativeToTop"} && $base eq '') {
    $base = '$(TOP/)';
  }
  $self->{base} = $base;

  $self->{auto_links_re} = undef;
  if (defined $self->{glossary}) {
    $_ = join ('|', $self->{glossary}->get_auto_link_keys());
    if ($_ ne '') { $self->{auto_links_re} = qr{$_}; }
  }

  # hmmm... tricky.  Since it's very easy to accidentally put an auto link key
  # inside HTML tags, for example if the key is "ntk" and the HTML tag is e.g.
  # "<a href=http://www.ntk.net>ntk</a>", we need to parse the document in a
  # more lex-ish style, and skip any text inside links or in HTML tags.

LOOP:
  {
    if ($$html =~ /\G([^<]+)/gsc) {
      $done .= $self->markup_ettext_segment($1);
      redo LOOP;
    }

    if ($$html =~ /\G(<a\s+href[^>]*>)(.*?)<\/a>/gisc) {
      $done .= $self->markup_a_href($1, $2).'</a>';
      redo LOOP;
    }

    if ($$html =~ /\G(<[^>]*>)/gsc) {
      $done .= $self->markup_html_segment($1);
      redo LOOP;
    }
  }

  $done =~ s{\Q${URL_PROTECTOR}\E}{}gs;
  $$html = $done;
}

sub markup_a_href {
  my ($self, $ahref, $linktext) = @_;
  $_ = $self->markup_html_segment($ahref);
  $_.$linktext;
}

sub markup_html_segment {
  my ($self) = shift;
  local ($_) = shift;

  # <foo@foo> addrs
  s{^<([-_\+\.\,\/\%\=A-Za-z0-9]+)(\@[-_\.A-Za-z0-9]+)>$}
        {<a href=\"mailto:${prot}$1${prot}$2\">$1${prot}$2</a>}gis;             
        #"

  # <URL:http://foo/> links.
  s{^<URL:(\S\S)([^>]+?)>$}
        {<a href=\"$1${prot}$2\">\&lt;URL:$1${prot}$2\&gt;</a>}gsx; #"

  s{(${ATTRS_WITH_URLS})\s*=\s*([\"\'])(.+?)([\"\'])}{ #"
    $1."=".$2._handle_link_href ($self->{base}, $3).$4;
  }geisx;
  s{(${ATTRS_WITH_URLS})\s*=\s*(.+?)(>|\s)}{
    $1."="._handle_link_href ($self->{base}, $2).$3;
  }geisx;
  $_;
}

sub markup_ettext_segment {
  my ($self) = shift;
  local ($_) = shift;

  # All links are converted into temporarily invalid URLs to protect them from
  # later substitutions, using the $prot string. This is taken out again at the
  # end of do_segmented_traverse().

  # http://foo links
  s{(http|file|ftp|https)(://\S+?)([\.]*(?:[\s\(\)\<\>\;\:\,]|$))}
        {<a href=\"$1${prot}$2\">$1${prot}$2</a>$3}gis; #"

  # mailto:foo@foo links
  s{(mailto:[-_\+\.\,\/\%\=A-Za-z0-9]+)
        (\@[-_\+\.\,\/\%\=A-Za-z0-9]+)
        ([\.\,\;\:\)]?(?:\s|$))}
        {<a href=\"$1${prot}$2\">$1${prot}$2</a>$3
        }gisx; #"

  # simple foo@foo addrs
  s{([-_\+\.\,\/\%\=A-Za-z0-9]+)(\@[-_\.A-Za-z0-9]+)\b}
        {<a href=\"mailto:${prot}$1${prot}$2\">$1${prot}$2</a>}gis; #"

  # auto links.
  my $glospat = $self->{auto_links_re};
  if (defined $glospat) {
    s{(^|[\s\(\)\[\]\'\=\+\;])(${glospat})([\s\(\)\[\]\'\=\+\/\.\,\?\!\&]|$)}{
      #'
      $1.$self->link_write (0, $2, $2).$3;
    }ges;
  }

  $_;
}

# ---------------------------------------------------------------------------

sub do_entities {
  my ($self, $html) = @_;
  local ($_);
  # fix ''real quoted bits''
  $$html =~ s,''(.*?)'',\"$1\",gs;		# fix vim:"

  # fix HTML entities, using the char2entity array from HTML::Entities.
  # we can't just use the encode_entities call as it'll break all <, >,
  # and & signs.
  $$html =~ s{([^\001-\037A-Za-z0-9\n\t !\#\$%\"\'-;=?-~<>&])}
  		{$HTML::Entities::char2entity{$1}}gs;

  # square-bracket entities.
  $$html =~ s/\&etsqi;/\[/gs;
  $$html =~ s/\&etsqo;/\]/gs;

  # less-than chars, etc. that are NOT part of HTML declarations;
  # the heuristic used is that spaces (or a line break) on both sides
  # of the sign indicate that it is not a HTML tag.
  $$html =~ s,(^| )< ,$1\&lt; ,gm;
  $$html =~ s,(^| )\& ,$1\&amp; ,gm;

  # ending tags often end with a space before the > sign.
  # Try to work it out using the text before the tag.
  $$html =~ s{(^| )>( )}{
    my $spcl = $1; my $spcr = $2; if ($` !~ /<[A-Za-z][^>]*$/m) {
      $spcl."&gt;".$spcr;
    } else {
      $spcl.">".$spcr;
    }
  }gme;
}

sub do_headings {
  my ($self, $html) = @_;
  local ($_);
  # do headings.
  $$html =~ s/(^\n+|\n\n)([^\n]+)[ \t]*\n-{3,}\n/$1<h2>$2<\/h2>\n\n/gs;
  $$html =~ s/(^\n+|\n\n)([^\n]+)[ \t]*\n={3,}\n/$1<h1>$2<\/h1>\n\n/gs;
  $$html =~ s/(^\n+|\n\n)([^\n]+)[ \t]*\n\~{3,}\n/$1<h3>$2<\/h3>\n\n/gs;
  $$html =~ s/(^\n+|\n\n)([0-9A-Z][^a-z]+)[ \t]*\n\n/$1<h3>$2<\/h3>\n\n/gs;

  # now create HRs. Currently we don't bother looking at the
  # character used, and so all hrs look the same; perhaps this
  # would be a TODO. Not yet though.
  $$html =~ s/\n-{10,} *\n/\n<hr \/>\n\n/gs;
  $$html =~ s/\n={10,} *\n/\n<hr \/>\n\n/gs;
  $$html =~ s/\n\~{10,} *\n/\n<hr \/>\n\n/gs;

  # break into paragraphs.
  $$html =~ s,\n\s*\n,\n</p>\n\n<p>,gs;

  # but HR tags or headings don't need paras.
  $$html =~ s{<p>\s*
	    (<hr(?:\s[^>]+|)>|<br(?:\s[^>]+|)>|<h\d>.*?<\/h\d>)
	    \s*<\/p>}
	    {$1}gisx;
  $$html =~ s{<p>\s*
	    ((?:<[^>]+>\s*)
	    *?)\s*<\/p>}
	    {$1}gisx;

  $$html =~ s{<(h\d)>\s*(.*?)\s*<\/h\d>}{
    "<a name=\"".sanitise_name($2)."\"><".$1.">".$2."</".$1."></a>";
  }geis;	#"

  $$html .= "</p>";
}

sub sanitise_name {
  my ($name) = shift;
  $name =~ s/[^-_A-Za-z0-9]/_/g;
  $name;
}

sub do_sidebars {
  my ($self, $html) = @_;

  # handle <etleft> and <etright> blocks, used to do sidebars
  # or images on paragraphs
  $$html =~ s{<p>\s*<etleft\s*>\s*(.*?)\s*</\s*etleft\s*>\s*(.*?)\s*</p>}
	{<table><tr>
	<td valign=top><p>$1</p></td>
	<td width=99% valign=top><p>$2</p></td>
	</tr></table>}gis;

  $$html =~ s{<p>\s*<etright\s*>\s*(.*?)\s*</\s*etright\s*>\s*(.*?)\s*</p>}
	{<table><tr>
	<td width=99% valign=top><p>$2</p></td>
	<td valign=top><p>$1</p></td>
	</tr></table>}gis;
}

sub do_final_cleanup {
  my ($self, $html) = @_;
  local ($_);

  # trim the spare para markers at start and end.
  $$html =~ s,^\s*</p>,,s;
  $$html =~ s,<p>\s*$,,s;
  $$html =~ s,^,<p>,s	unless ($$html =~ m,^\s*<p>,);
  $$html =~ s,$,</p>,s	unless ($$html =~ m,<\/p>\s*$,);

  # Remove <p> tags around blocks that do not contain any real text,
  # and are instead just blocks of HTML tags.
  $$html =~ s{<p>(.*?)<\/p>}{
    $_ = $1;
    if (/>[^<]*\S/) {
      "<p>" . $_ . "</p>";
    } elsif (!/>/) {
      "<p>" . $_ . "</p>";
    } else {
      $_;
    }
  }geis;

  # trim para markers before the <html> tag, in case one was
  # present in the doc to start with. Ditto for after the </html>.
  $$html =~ s,^\s*<(?:/p|p)>\s*<(doctype|html),<$1,is;
  $$html =~ s,(<\/html>)\s*<(?:/p|p)>\s*$,$1,is;
}

sub link_write {
  my ($self, $was_glossary_link, $linklabel, $text) = @_;
  my $url;

  # see if the link label was a proper link specification instead
  # of a symbolic one. Don't do this if it was wrapped by quotes,
  # though.
  if (defined $linklabel && !$was_glossary_link &&
    $linklabel =~ /^(?:\$|http:|file:|ftp:)/i)
  {
    $url = $linklabel; goto gotone;
  }

  # check to see if there was a link label at all -- if
  # there wasn't, we could have been a glossary link.
  $linklabel ||= $text;

  if (defined (($url = $self->{links}->{$linklabel}))) {
    goto gotone;
  }
  elsif (defined (($url = $self->{auto_links}->{$linklabel}))) {
    goto gotone;
  }
  elsif (defined ($self->{glossary}) &&
      defined ($url = $self->{glossary}->get_auto_link($linklabel)))
  {
    goto gotone;
  }
  elsif (length $linklabel > 3 &&
      defined ($self->{glossary}) &&
      defined ($url = $self->{glossary}->get_link($linklabel)))
  {
    goto gotone;
  }
  elsif ($was_glossary_link)
  {
    warn "Link not found (use ''quotes'' to avoid warning): \"$linklabel\"\n";
    return $text;
  }
  else
  {
    return $text;
  }

gotone:
  return "<a href=\"".$url."\">".$text."</a>";
}

###########################################################################

sub protect_html {
  my ($self, $html) = @_;
  $$html =~ s/ /\016\001/gs;
  $$html =~ s/\t/\016\002/gs;
  $$html =~ s/</\016\003/gs;
  $$html =~ s/>/\016\004/gs;
  $$html =~ s/\&/\016\005/gs;
  $$html =~ s/\"/\016\006/gs;
  $$html =~ s/\'/\016\007/gs;
  $$html =~ s/\//\016\010/gs;
  # skip 010-015, they're commonly used
  $$html =~ s/:/\016\017/gs;
  $$html =~ s/\n/\016\020/gs;
  $$html =~ s/\[/\016\021/gs;
}

###########################################################################

sub unprotect_html {
  my ($self, $html) = @_;
  $$html =~ s/\016\001/ /gs;
  $$html =~ s/\016\002/\t/gs;
  $$html =~ s/\016\003/</gs;
  $$html =~ s/\016\004/>/gs;
  $$html =~ s/\016\005/\&/gs;
  $$html =~ s/\016\006/\"/gs;
  $$html =~ s/\016\007/\'/gs;
  $$html =~ s/\016\010/\//gs;
  # skip 010-015, they're commonly used
  $$html =~ s/\016\017/:/gs;
  $$html =~ s/\016\020/\n/gs;
  $$html =~ s/\016\021/[/gs;
}

###########################################################################

sub markup_lists {
  my ($self, $orightml) = @_;
  local ($_);
  my $html = '';

  # these are:
  # the tag stack indicating which close tag we need to use at end of block
  $self->{list_tag} = [ ];
  # the indentation level of the current block, in spaces.
  $self->{list_indent} = [ ];
  # the optional alternative indent level for the current block.
  # invariant: must be >= {list_indent}.
  $self->{list_alternative_indent} = [ ];

  # strip obsolete list-opening tags.
  $orightml =~ s/^<(?:ul|ol|\/ul|\/ol)>//gim;
  
  # we need to do this line-by-line, it's a LOT easier.
  foreach $_ (split (/\n/, $orightml)) {

    if (s/^<p>([ \t]+)//) {
      my ($indent, $rest) = ($1, $');
      $indent =~ s/\t/        /g;
      $html .= $self->indent_item_start (length ($indent), $rest, 1) . "\n";
    }
    elsif (s/^<\/p>//) {
      $html .= $self->indent_item_end () . $_ . "\n";
    }
    elsif (s/^<p>::(\s)//) {
      my $rest = '::'.$1.$';
      my $pre = $self->indent_item_end () . "\n";
      my $postfix = $self->indent_item_start (0, $rest, 0) . "\n";
      $html .= $pre . $postfix;
    }
    elsif (/^</) {
      $html .= $self->indent_list_end () . $_ . "\n";
    }
    elsif (s/^([ \t]+)([-\*\+o]|\d+\.)(\s)//) {
      my ($indent, $rest) = ($1, $2.$3.$');
      $indent =~ s/\t/        /g;
      my $pre = $self->indent_item_end () . "\n";
      my $postfix = $self->indent_item_start (length ($indent),
      							$rest, 0) . "\n";
      $html .= $pre . $postfix;
    }
    elsif (s/^::\s//) {
      $html .= $_ . "\n";
    }
    else {
      $html .= $_ . "\n";
    }
  }

  $html .= $self->indent_item_end () . $self->indent_list_end (). "\n";

  undef $self->{list_alternative_indent};
  undef $self->{list_indent};
  undef $self->{list_tag};
  $html;
}

sub indent_item_start {
  my ($self, $indent, $line, $hasptag) = @_;

  my $listblock = undef;
  my $closeitemtag = undef;
  my $alt_indent = 0;
  $self->get_current_indent_level();

  my $openptag = '';
  my $closeptag = '';
  if ($hasptag) { $openptag = '<p>'; $closeptag = '</p>'; }

  if ($line =~ s/^[-\*\+o](\s+)//) {
    $listblock = 'ul';
    $closeitemtag = '</li>';
    $alt_indent = $indent+length($1)+1;
    $line = "<li>".$openptag.$line;
  }
  elsif ($line =~ s/^\d+\.(\s+)//) {
    $listblock = 'ol';
    $closeitemtag = '</li>';
    $alt_indent = $indent+length($1)+2;
    $line = "<li>".$openptag.$line;
  }
  elsif ($line =~ s/^(.+?):\t\s*//) {		# definition lists.
    $listblock = 'dl';
    $closeitemtag = '</dd>';
    $line = "<dt>$1</dt><dd>".$openptag.$line;
  }
  elsif ($indent == 1 || ($indent == 0 && $line =~ s/^::\s//)) {
    $closeitemtag = '</pre>';
    $line = "<pre>".$line;
    $openptag = ''; $closeptag = '';
  }
  else {
    $closeitemtag = '</blockquote>';
    $line = "<blockquote>".$openptag.$line;
  }
  $self->{current_item_cls_tag} = $closeptag.$closeitemtag;

  if (defined $listblock) {
    if ($indent > $self->{curindent} && $indent != $self->{curaltindent})
    {
      $line = $self->push_indent_level ($listblock,
      			$alt_indent, $indent, $line);
    }
    elsif ($indent < $self->{curindent}) {
      while ($indent < $self->{curindent}) {
	$line = $self->pop_indent_level ($self->{curbloctag}, $line);
      }
    }
  }

  $line;
}

sub indent_item_end {
  my ($self) = @_;

  if (defined $self->{current_item_cls_tag}) {
    my $ret = $self->{current_item_cls_tag};
    $self->{current_item_cls_tag} = undef;
    return $ret;

  } else {
    return '</p>';
  }
}

sub indent_list_end {
  my ($self) = @_;
  my $line = '';

  $self->get_current_indent_level();
  while (0 < $self->{curindent}) {
    $line = $self->pop_indent_level ($self->{curbloctag}, $line);
  }
  $line;
}

sub get_current_indent_level {
  my ($self) = @_;

  $self->{curbloctag} = ${$self->{list_tag}}[0];
  $self->{curindent} = ${$self->{list_indent}}[0];
  $self->{curaltindent} = ${$self->{list_alternative_indent}}[0];
  $self->{curindent} ||= 0;
  $self->{curaltindent} ||= 0;
}

sub push_indent_level ($$$$$) {
  my ($self, $listblock, $altindent, $indent, $line) = @_;

  unshift (@{$self->{list_alternative_indent}}, $altindent);
  unshift (@{$self->{list_indent}}, $indent);
  unshift (@{$self->{list_tag}}, $listblock);
  $self->get_current_indent_level();
  "<$listblock>" . $line;
}

sub pop_indent_level {
  my ($self, $listblock, $line) = @_;

  shift (@{$self->{list_alternative_indent}});
  shift (@{$self->{list_indent}});
  shift (@{$self->{list_tag}});
  $self->get_current_indent_level();
  "</$listblock>" . $line;
}

###########################################################################

1;

__END__

=back

=head1 MORE DOCUMENTATION

See also http://webmake.taint.org/ for more information.

=head1 SEE ALSO

C<webmake>
C<ettext2html>
C<ethtml2text>
C<HTML::WebMake>
C<Text::EtText::EtText2HTML>
C<Text::EtText::HTML2EtText>
C<Text::EtText::LinkGlossary>
C<Text::EtText::DefaultGlossary>

=head1 AUTHOR

Justin Mason E<lt>jm /at/ jmason.orgE<gt>

=head1 COPYRIGHT

WebMake is distributed under the terms of the GNU Public License.

=head1 AVAILABILITY

The latest version of this library is likely to be available from CPAN
as well as:

  http://webmake.taint.org/

=cut

