use Data::Dumper;
use Cwd;
use strict;

## Loop through all subdirectories of the parameter, returning the names of the directories
## containing java files.

# The results will be put in here.
my @retVal;
# This will contain the directories to process.
my @stack = @ARGV;
# For each directory, stack its subdirectories, and output it if it contains java files.
while (scalar @stack) {
    my $dir = pop @stack;
    if (opendir(my $dh, $dir)) {
        my @entries = grep { substr($_,0,1) ne '.' } readdir $dh;
        closedir $dh;
        my $keep;
        for my $entry (@entries) {
            if ($entry =~ /\.java$/) {
                $keep = 1;
            } elsif (-d "$dir/$entry") {
                push @stack, "$dir/$entry";
            }
        }
        if ($keep) {
            push @retVal, $dir;
        }
    }
}
# Output the results.
for my $dir (@retVal) {
    print "$dir\n";
}
