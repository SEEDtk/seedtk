use Data::Dumper;
use File::Basename;
use strict;
use Graph;

our $have_topo = 0;
eval {
	require Sort::Topological;
	Sort::Topological->import('toposort');
	$have_topo = 1;
};
use List::MoreUtils 'part';

#
# Determine the correct order of module builds based on the
# DEPENDENCIES files in the modules.
#

my $modules_dir = shift;
my $graph = Graph->new;

my @mods;
my %children;
sub children
{
    my($x) = @_;
    my @s = $graph->predecessors($x);
    return @s;
}

for my $mf (<$modules_dir/*/Makefile>)
{
    my $mdir = dirname($mf);
    my $mod = basename($mdir);

    $graph->add_vertex($mod);

    if (open(D, "<", "$mdir/DEPENDENCIES"))
    {
	while (<D>)
	{
	    chomp;
	    if (my($new) = /(\S+)/)
	    {
		$graph->add_vertex($new);
		$graph->add_edge($mod, $new);
		# push(@{$children{$1}}, $mod);
	    }
	}
	close(D);
    }
    push(@mods, $mod);
}

#
# Search for loops.
#
while ($graph->has_a_cycle)
{

    my @c = $graph->find_a_cycle();
    warn "Removing dependency cycle: @c\n";
    $graph->delete_cycle(@c);
}

for my $mod (@mods)
{
    my %seen;
    $seen{$mod} = 1;

}

my @sorted;
if ($have_topo)
{
    @sorted = toposort(\&children, \@mods);
}
else
{
    @sorted = @mods;
}

#
# If there is an entry for the type compiler and kb_seed, bubble them up to the
# top of the list.
#

my($typecomp_ar, $kb_seed_ar, $rest) = part {
	$_ eq 'typecomp' ? 0 : ( $_ eq 'kb_seed' ? 1 : 2); } @sorted;
$typecomp_ar ||= [];
$kb_seed_ar ||= [];
$rest ||= [];
@sorted = (@$typecomp_ar, @$kb_seed_ar, @$rest);
print "$_\n" foreach @sorted;
