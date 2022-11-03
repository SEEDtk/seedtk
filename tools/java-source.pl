use Data::Dumper;
use Cwd;
use strict;

## Loop through all subdirectories of the parameter, returning the names of the directories
## containing java files.

# The results will be put in here.
my @retVal;
# This will contain the directories to process.
my @stack = @ARGV;
# For each directory, stack its subdirectories, and output the java files.
while (scalar @stack) {
    my $dir = pop @stack;
    if (opendir(my $dh, $dir)) {
        my @entries = grep { substr($_,0,1) ne '.' } readdir $dh;
        closedir $dh;
        for my $entry (@entries) {
            if ($entry =~ /\.java$/) {
                push @retVal, "$dir/$entry";
            } elsif (-d "$dir/$entry") {
                push @stack, "$dir/$entry";
            }
        }
    }
}
# Output the results.
my $count = scalar @retVal;
for my $file (@retVal) {
    print "$file\n";
}
