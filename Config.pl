#!/usr/bin/env perl

#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

use strict;
use File::Basename;
use File::Spec;
use File::Copy;
use File::Copy::Recursive;
use File::Path;
use Getopt::Long::Descriptive;
use XML::Writer;
use IO::File;
use Config;
use Cwd;

# We need to look inside the FIG_Config even though it is loaded at
# run-time, so we will get lots of warnings about one-time variables.
no warnings qw(once);

## THIS CONSTANT DEFINES THE CORE MODULES
use constant CORE => qw(utils ERDB kernel p3_code RASTtk tbltools);

## THIS CONSTANT DEFINES MODULES WITH SPECIAL INCLUDE LISTS
use constant INCLUDES => { utils => ['utils', 'RASTtk', 'p3_code'], RASTtk => ['RASTtk', 'utils', 'p3_code'],
                           p3_code => ['p3_code'] };

=head1 Generate SEEDtk Configuration Files

    Config [ options ] dataDirectory webDirectory

This method generates (or re-generates) the L<FIG_Config> and B<UConfig.sh> files for a
SEEDtk environment.

=head2 Parameters

The positional parameters are the location of the data folder and the location
of the web folder (see L<ReadMe> for more information about SEEDtk folders). If a
B<FIG_Config> file already exists, this information is not needed-- the existing values
will be used.

The command-line options are as follows.

=over 4

=item fc

If specified, the name of the B<FIG_Config> file for the output. If the name is specified
without a path, it will be put in the project directory's C<config> folder. If C<off>,
no B<FIG_Config> file will be written.

=item clear

If specified, the current B<FIG_Config> values will be ignored, and the configuration information will
be generated from scratch.

=item links

If specified, a prototype C<Links.html> file will be generated in the web directory if one does not
already exist.

=item dirs

If specified, the default data and web subdirectories will be set up.

=item dna

If specified, the location for the DNA repository. If you are using a shared database, then
this insures you are using the same repository as everyone else. If C<none>, then the DNA
repository is turned off and DNA requests will fail.

=item eclipse

If this is an Eclipse environment, the name of the project cloned from the main SEEDtk
project (that is, the name of the I<project directory project>). If you specify this
parameter without a value, the value is presumed to by C<SEEDtk>.

=item gfw

If this is specified, then it is presumed you have GitHub for Windows installed. Its copy of
GIT will be added to your path in the C<user-env> script.

=item dbhost

Name of the database host on which the database will be placed. The default is C<localhost>.

=item dbname

Name to give to the shrub database. The default is an empty string, meaning the default name will
be used.

=item dbuser

User name for signing on to the database. The default is C<seed>.

=item dbpass

Password for signing on to the database. The default is an empty string, meaning no password.

=item kbase

Name of a directory in which to create a shadow FIG_Config for the kbase environment.

=item remoteWeb

If specified, the web directory will be cleared and reloaded from GIT, then updated
with an explicit PERL path in the shebang header. This is useful when the default PERL
will not work on the web. The resulting web directory cannot be refreshed from GIT
without destroying the site. Instead, it must be updated using this script. This option
is only for Unix. In Windows, the shebang line is not used.


=back

=head2 Notes for Programmers

To add a new L<FIG_Config> parameter, simply add a call to L<Env/WriteParam> to the
L</WriteAllParams> method.


=cut

$| = 1; # Prevent buffering on STDOUT.
# Determine the operating system.
my $winMode = ($^O =~ /Win/ ? 1 : 0);
# Analyze the command line.
my ($opt, $usage) = describe_options('%o %c dataRootDirectory webRootDirectory',
        ["clear|c", "ignore current configuration values"],
        ["fc=s", "name of a file to use for the FIG_Config output, or \"off\" to turn off FIG_Config output",
                { default => "FIG_Config.pm" }],
        ["dirs", "verify default subdirectories exist"],
        ["dna=s", "location of the DNA repository (if other than local)"],
        ["dbhost=s", "name of the database host to which we should connect", { default => 'localhost' }],
        ["links", "generate Links.html file"],
        ["gfw", "add GitHub for Windows GIT to the path (Windows only)"],
        ["gitbash", "configure for gitbash use"],
        ["dbname=s", "Shrub database name"],
        ["dbuser=s", "Shrub database user", { default => 'seed' }],
        ["dbpass=s", "Shrub database password"],
        ["kbase=s", "kbase lib directory"],
        ["eclipse:s", "if specified, then we will set up for Eclipse"],
        ["remoteWeb", "if specified, the web directory will be configured as a remote web site (Unix only)"],
        ["homeFix", "if specified, a root path of 'homes' will be changed to 'home' (Argonne kludge)"]
        );
print "Retrieving current configuration.\n";
# Compute the eclipse option.
my $eclipseMode;
my $eclipseParm = $opt->eclipse;
if (defined $eclipseParm) {
    $eclipseMode = 1;
    if (! $eclipseParm) {
        $eclipseParm = 'SEEDtk';
    }
}
# Get the directory this script is running in.
my $base_dir = dirname(File::Spec->rel2abs(__FILE__));
# Get into it.
chdir $base_dir;
# Compute the remote base directory.
my $rstr = `git remote -v`;
my($remote) = $rstr =~ /^origin\s+(\S+)/;
my $remote_base = dirname($remote);
# Get the real base directory. For Unix, this is the project
# directory. For vanilla mode, this is the project directory's
# parent. We will also figure out the eclipse mode here.

my ($vanillaMode, $projName, $dataParm, $webParm);
if ($ENV{KB_TOP}) {
    # Here we are in a Unix setup. The base directory has been
    # stored in the environment.
    $base_dir = $ENV{KB_TOP};
    ($dataParm, $webParm) = @ARGV;
} else {
    # Clean up the incoming path names.
    if ($ARGV[0]) {
        $dataParm = File::Spec->rel2abs($ARGV[0]);
    }
    if ($ARGV[1]) {
        $webParm = File::Spec->rel2abs($ARGV[1]);
    }
    # Fix Windows slash craziness.
    $base_dir =~ tr/\\/\//;
    # Check our directory name.
    $projName = $eclipseParm || 'SEEDtk';
    if ($base_dir =~ /(.+)\/$projName/) {
        $base_dir = $1;
    } else {
        die "Configuration script not found in $projName.";
    }
}
if ($opt->homefix) {
    $base_dir =~ s#/homes/#/home/#;
    print "Fixing home directory.\n";
}
print "Base directory is $base_dir.\n";
if (! $ENV{KB_TOP}) {
    # Denote this is vanilla mode.
    $vanillaMode = 1;
    # Do we need to bootstrap?
    my $libDir = "$base_dir/utils/lib";
    if (! -f "$libDir/Env.pm") {
        # Yes. Clone everything.
        print "Check out from $remote_base\n";
        chdir $base_dir;
        for my $module (CORE) {
            my $url = "$remote_base/$module.git";
            print "Cloning $module from $url.\n";
            my $rc = system("git", "clone", $url);
            if ($rc != 0) {
                die "Error cloning $url\n";
            }
        }
        if ($webParm) {
            # Here we want a web directory.
            print "Web directory will be generated in current location.\n";
            system("git", "clone", "$remote_base/Web.git");
            # Compute the real web directory.
            $webParm = "$base_dir/Web/Web";
        }
    }
    # Get access to the utilities library.
    unshift @INC, $libDir;
}
# Load the environment library.
require Env;
print "Analyzing directories.\n";
# The root directories will be put in here.
my ($dataRootDir, $webRootDir) = ('', '');
# This points to the project directory project.
my $projDir = ($vanillaMode ? join("/", $base_dir, $projName) : $base_dir);
if (! -d "$projDir/config") {
    die "Project directory not found in $projDir.";
}
# Save the current environment, before it's been modified by FIG_Config.
my %oldenv = %ENV;
# Get the name of the real FIG_Config file (not the output file,
# if one was specified, the real one).
my $fig_config_name = "$projDir/config/FIG_Config.pm";
# Now we want to get the current environment. If the CLEAR option is
# specified or there is no file present, we stay blank; otherwise, we
# load the existing FIG_Config.
if (! $opt->clear && -f $fig_config_name) {
    RunFigConfig($fig_config_name);
}
# Insure the list of modules includes the cores. If they are not
# present, we add them to the front of the list.
for my $module (CORE) {
    if (! grep { $_ eq $module } @FIG_Config::modules) {
        unshift @FIG_Config::modules, $module;
    }
}
# This hash will map each module to its directory.
my $modBaseDir = ($vanillaMode ? $base_dir : "$projDir/modules");
my %modules;
for my $module (@FIG_Config::modules) {
    # Compute the directory name depending on the mode.
    my $dir = "$modBaseDir/$module";
    # Make sure it exists.
    if (! -d $dir) {
        die "Could not find expected module directory $dir.";
    }
    # Add it to the hash.
    $modules{$module} = $dir;
}
# Check for older files that use a different name for FIG_Config::data.
if (! defined $FIG_Config::data && $FIG_Config::shrub_dir) {
    $FIG_Config::data = $FIG_Config::shrub_dir;
}
# Make sure we have the data directory if there is no data root
# in the command-line parameters.
if (! defined $FIG_Config::data) {
    $dataRootDir = FixPath($ARGV[0]);
    if (! defined $dataRootDir) {
        die "A data root directory is required if no current value exists in FIG_Config.";
    } elsif (! -d $dataRootDir) {
        print "Creating $dataRootDir\n";
        File::Copy::Recursive::pathmk($dataRootDir) || die "Could not create $dataRootDir: $!";
    }
} else {
    $dataRootDir = $FIG_Config::data;
}
# Make sure we have the web directory if there is no web root in
# the command-line parameters.
if (! defined $FIG_Config::web_dir) {
    if (! $ARGV[1]) {
        $webRootDir = '';
    } else {
        $webRootDir = FixPath($ARGV[1]);
        if (! -d $webRootDir) {
            die "The specified web root directory $webRootDir was not found.";
        }
    }
} else {
    $webRootDir = $FIG_Config::web_dir;
}
# Insure we have the Alexa workspaces.
my $alexaDir = $FIG_Config::alexa // "$dataRootDir/AlexaSpaces";
if (! -d $alexaDir) {
    File::Copy::Recursive::pathmk($alexaDir);
    if (! $winMode) {
        chmod 0777, $alexaDir;
    }
}
# If this is a remote web situation, we need to re-create the web directory here.
if ($opt->remoteweb) {
    if (! -d $webRootDir) {
        die "Web root directory $webRootDir does not exist.";
    }
    print "Clearing $webRootDir.\n";
    File::Copy::Recursive::pathempty($webRootDir);
    # We have to pull the web stuff into a temporary location and then copy it over, modifying the
    # CGI files as we go. This is pretty complicated. First, we need to know the perl location.
    my $perl_loc = `which perl`;
    # Now we pull the web project directly into the SEEDtk directory.
    my $webSource = "$base_dir/Web/Web";
    if (-f "$webSource/index.html") {
        chdir "$base_dir/Web";
        print "Refreshing source web directory.\n";
        system("git", "pull");
    } else {
        chdir $base_dir;
        print "Retrieving source web directory.\n";
        system("git", "clone", "$remote_base/Web.git");
    }
    # Copy the web directory.
    opendir(my $dh, $webSource) || die "Could not open web source directory $webSource: $!";
    # Get all the objects in it that are not hidden.
    my @webItems = grep { substr($_,0,1) ne '.' } readdir $dh;
    for my $webItem (@webItems) {
        my $itemPath = "$webSource/$webItem";
        my $destPath = "$webRootDir/$webItem";
        if (-d $itemPath) {
            print "Copying directory $webItem.\n";
            File::Copy::Recursive::dircopy($itemPath, $destPath);
        } elsif ($webItem =~ /\.cgi$/) {
            # Here we have a CGI script, which we copy manually.
            print "Converting $webItem.\n";
            open(my $ih, "<$itemPath") || die "Could not open $itemPath: $!";
            open(my $oh, ">$destPath") || die "Could not open $destPath: $!";
            while (! eof $ih) {
                my $line = <$ih>;
                if ($line =~ /^#!.+perl/) {
                    print $oh "#!$perl_loc\n";
                } else {
                    print $oh $line;
                }
            }
            # Fix the permissions.
            chmod 0755, $destPath;
        } else {
            # Normal files are copied normally.
            print "Copying file $webItem.\n";
            File::Copy::Recursive::fcopy($itemPath, $destPath);
        }
    }
    # Copy the Links.html if needed.
    if (! -f "$webRootDir/Links.html") {
        print "Creating Links.html.\n";
        File::Copy::Recursive::fcopy("$webSource/lib/Links.html", "$webRootDir/Links.html") ||
            die "Could not copy links file: $!";
    }
    # Insure we have a temp directory.
    my $tmpDir = $FIG_Config::temp;
    if (! -d $tmpDir) {
        File::Copy::Recursive::pathmk($tmpDir);
        if (! $winMode) {
            chmod 0777, $tmpDir;
        }
    }
}
#If the FIG_Config write has NOT been turned off, then write the FIG_Config.
if ($opt->fc eq 'off') {
    print "FIG_Config output suppressed.\n";
} else {
    # Compute the FIG_Config file name.
    my $outputName = $opt->fc;
    # Fix the slash craziness for Windows.
    $outputName =~ tr/\\/\//;
    # If the name is pathless, put it in the config directory.
    if ($outputName !~ /\//) {
        $outputName = "$projDir/config/$outputName";
    }
    # If we are overwriting the real FIG_Config, back it up.
    if (-f $fig_config_name && $outputName eq $fig_config_name) {
        print "Backing up $fig_config_name.\n";
        copy $fig_config_name, "$projDir/config/FIG_Config_old.pm";
    }
    # Write the FIG_Config.
    print "Writing configuration to $outputName.\n";
    WriteAllParams($outputName, $modBaseDir, \%modules, $projDir, $dataRootDir, $webRootDir, $alexaDir, $winMode, $opt);
    # Execute it to get the latest variable values.
    print "Reading back new configuration.\n";
    RunFigConfig($outputName);
    # Check for a KBase shadow.
    if ($opt->kbase) {
        my $kbFigConfig = $opt->kbase;
        # Create a module directory map.
        my $kbModBase = "/kb/module/SEEDtk/modules";
        my %kbModules;
        for my $module (@FIG_Config::modules) {
            $kbModules{$module} = "$kbModBase/$module";
        }
        WriteAllParams($kbFigConfig, $kbModBase, \%kbModules, '/kb/module/SEEDtk', '/kb/module/SEEDtk/Data',
                '', '', 0, $opt, 1);
    }
}
# Are we setting up default data directories?
if ($opt->dirs) {
    # Yes. Insure we have the data paths.
    BuildPaths($winMode, Data => $FIG_Config::data, qw(Inputs Inputs/GenomeData Inputs/SubSystemData LoadFiles));
    # Are we using a local DNA repository?
    if (! $opt->dna) {
        # Yes. Build that, too.
        BuildPaths($winMode, Data => $FIG_Config::data, qw(DnaRepo));
    }
    # Insure we have the web paths.
    if ($webRootDir) {
        BuildPaths($winMode, Web => $FIG_Config::web_dir, qw(img Tmp logs));
    }
}
# Insure we have the global directory path.
if (! -d $FIG_Config::global) {
    print "Creating $FIG_Config::global.\n";
    File::Path::make_path($FIG_Config::global)
}
BuildPaths($winMode, Data => $FIG_Config::data, qw(Global));
# Insure we have the eval/binning directory path.
if (! -d $FIG_Config::p3data) {
    print "Creating $FIG_Config::p3data.\n";
    File::Path::make_path($FIG_Config::p3data);
}
BuildPaths($winMode, Data => $FIG_Config::data, qw(P3Data));
# Do we have a Web project?
if ($webRootDir) {
    my $weblib = "$FIG_Config::web_dir/lib";
    if (-d $weblib) {
        # Yes. Create the web configuration files.
        my $webConfig = "$weblib/Web_Config.pm";
        my $jobConfig = "$projDir/config/Job_Config.pm";
        # Open the web configuration file for output.
        my ($oh1, $oh2);
        if (! open(my $oh1, ">$webConfig")) {
            # Web system problems are considered warnings, not fatal errors.
            warn "Could not open web configuration file $webConfig: $!\n";
        } elsif (! open(my $oh2, ">$jobConfig")) {
            warn "Could not open background job configuration file $jobConfig: $!\n";
        } else {
            # Write the files.
            for my $oh ($oh1, $oh2) {
                print $oh "\n";
                print $oh "use lib\n";
                print $oh "    '" .     join("',\n    '", @FIG_Config::libs) . "';\n";
                print $oh "\n";
                print $oh "use FIG_Config;\n";
                print $oh "\n";
                print $oh "1;\n";
                # Close the file.
                close $oh;
            }
            print "Web configuration files $webConfig and $jobConfig created.\n";
        }
    }
}
# If this is vanilla mode, we need to set up the PERL libraries and
# execution paths.
if ($vanillaMode) {
    # Set up the paths and PERL libraries.
    WriteAllConfigs($winMode, \%modules, $projDir, $opt, \%oldenv);
    if (! $winMode) {
        # For an vanilla Mac installation, we have to set up binary versions of the scripts
        # and make them executable.
        SetupBinaries($projDir, \%modules, $opt);
        # We also need to fix the CGI permissions.
        SetupCGIs($FIG_Config::web_dir, $opt);
    } else {
        # For a vanilla Windows installation, we have to set up DOS-style version of the
        # shell scripts.
        SetupCommands(\%modules, $opt);
    }
} else {
    # For the alternate environment, we need to generate the Config script.
    SetupScript('Config.pl', "$projDir/bin", $projDir);
    # Then we need to do a make.
    my $oldDir = getcwd();
    chdir $projDir;
    system("make");
    chdir $oldDir;
}
# Setup the java commands.
SetupJava("$modules{kernel}/jars", $projDir);
# Now we need to create the pull-all script.
my $fileName = ($winMode ? "$projDir/pull-all.cmd" : "$projDir/bin/pull-all");
open(my $oh, ">$fileName") || die "Could not open $fileName: $!";
# The pushd command in windows can't handle forward slashes in directory names,
# so if this is windows we have to translate.
my $projDirForPush = $projDir;
if ($winMode) {
    # Windows, so we translate.
    $projDirForPush =~ tr/\//\\/;
    # We also want to turn off echoing.
    print $oh "\@echo off\n";
} else {
    # In Unix, we need the shebang.
    print $oh "#!/usr/bin/env bash\n";
}
# Now write the commands to run through the directories and pull.
print $oh "echo Pulling project directory.\n";
print $oh "pushd $projDirForPush\n";
print $oh "git pull\n";
for my $module (@FIG_Config::modules) {
    print $oh "echo Pulling $module\n";
    print $oh "cd $modules{$module}\n";
    print $oh "git pull\n";
}
# Add the Alexa directory.
if (-d "$modBaseDir/Alexa") {
    print $oh "echo Pulling Alexa directory\n";
    print $oh "cd $modBaseDir/Alexa\n";
    print $oh "git pull\n";
}
# Add the java directories.
for my $javaDir (@FIG_Config::java) {
    print $oh "echo Pulling java directory $javaDir\n";
    print $oh "cd $modBaseDir/$javaDir\n";
    print $oh "git pull\n";
}
# Add the web directory if needed.
if ($FIG_Config::web_dir && ! $ENV{KB_TOP} && ! $opt->remoteweb) {
    print $oh "echo Pulling web directory\n";
    print $oh "cd $FIG_Config::web_dir\n";
    print $oh "git pull\n";
}
# Restore the old directory.
print $oh "popd\n";
close $oh;
# In Unix, set the permissions.
if (! $winMode) {
    chmod 0755, $fileName;
}
print "Pull-all script written to $fileName.\n";
# Finally, check for the links file.
if ($opt->links) {
    if (! $webRootDir) {
        die "Web support is required if --links is specified.";
    }
    # Determine the output location for the links file.
    my $linksDest = "$FIG_Config::web_dir/Links.html";
    # Do we need to generate a links file?
    if (-f $linksDest) {
        # No need. We already have one.
        print "$linksDest file already exists-- not updated.\n";
    } else {
        # We don't have a links file yet.
        print "Generating new $linksDest.\n";
        # Find the source copy of the file.
        my $linksSrc = "$FIG_Config::web_dir/lib/Links.html";
        # Copy it to the destination.
        copy $linksSrc, $linksDest;
        print "$linksDest file created.\n";
    }
}
# We are done.
print "All done.\n";
# Display the user-env command syntax.
if ($vanillaMode) {
    my $cmd = "$FIG_Config::proj/user-env";
    if (! $winMode) {
        $cmd = "source $cmd.sh";
    }
    print "\nUse\n\n    $cmd\n\nto establish a command-line environment.\n";
}


=head2 Internal Subroutines

=head3 RunFigConfig

    RunFigConfig($fileName);

Execute the L<FIG_Config> module. This uses the PERL C<do> function, which
unlike C<require> can execute a module more than once, but requires error
checking. The error checking is done by this method.

=over 4

=item fileName

The name of the B<FIG_Config> file to load.

=back

=cut

sub RunFigConfig {
    # Get the parameters.
    my ($fileName) = @_;
    # Execute the FIG_Config;
    do $fileName;
    if ($@) {
        # An error occurred compiling the module.
        die "Error compiling FIG_Config: $@";
    } elsif ($!) {
        # An error occurred reading the module.
        die "Error reading FIG_Config: $!";
    }
}

=head3 WriteAllParams

    WriteAllParams($fig_config_name, $modBaseDir, \%modules, $projDir,
                   $dataRootDir, $webRootDir, $winMode, $opt, $force);

Write out the B<FIG_Config> file to the specified location. This method
is mostly calls to the L</WriteParam> method, which provides a concise
way of writing parameters to the file and checking for pre-existing
values. It is presumed that L</RunFigConfig> has been executed first so
that the existing values are known.

=over 4

=item fig_config_name

File name for the B<FIG_Config> file. The parameter code will be written to
this file.

=item modBaseDir

Base directory for the program modules.

=item modules

Reference to a hash mapping each module name to its directory.

=item projDir

Name of the project directory.

=item dataRootDir

Location of the base directory for the data files.

=item webRootDir

Location of the base directory for the web files.

=item winMode

TRUE for Windows, FALSE for Unix/Mac.

=item opt

Command-line options object.

=item kbase

If TRUE, the file will be modified for KBase use.

=back

=cut

sub WriteAllParams {
    # Get the parameters.
    my ($fig_config_name, $modBaseDir, $modules, $projDir, $dataRootDir, $webRootDir, $alexaDir, $winMode, $opt, $kbase) = @_;
    # Open the FIG_Config for output.
    open(my $oh, ">$fig_config_name") || die "Could not open $fig_config_name: $!";
    # Write the initial lines.
    print $oh "package FIG_Config;\n";
    Env::WriteLines($oh,
        "",
        "## WHEN YOU ADD ITEMS TO THIS FILE, BE SURE TO UPDATE kernel/scripts/Config.pl.",
        "## All paths should be absolute, not relative.",
        "");
    # Write each parameter.
    Env::WriteParam($oh, 'root directory of the local web server', web_dir => $webRootDir, $kbase);
    if ($webRootDir) {
        Env::WriteParam($oh, 'directory for temporary files', temp => "$webRootDir/Tmp", $kbase);
        Env::WriteParam($oh, 'URL for the directory of temporary files', temp_url => 'http://fig.localhost/Tmp');
        Env::WriteParam($oh, 'directory for Alexa workspaces', alexa => $alexaDir);
    }
    Env::WriteParam($oh, 'TRUE for windows mode', win_mode => ($winMode ? 1 : 0));
    Env::WriteParam($oh, 'source code project directory', proj => $projDir, $kbase);
    Env::WriteParam($oh, 'location of shared code', cvsroot => '');
    Env::WriteParam($oh, 'TRUE to switch to the data directory during setup', data_switch => 0);
    Env::WriteParam($oh, 'location of global file directory', global => "$dataRootDir/Global", $kbase);
    Env::WriteParam($oh, 'location of eval/binning file directory', p3data => "$dataRootDir/P3Data", $kbase);
    Env::WriteParam($oh, 'default conserved domain search URL', ConservedDomainSearchURL => "http://maple.mcs.anl.gov:5600");
    Env::WriteParam($oh, 'Patric Data API URL', p3_data_api_url => '');
    Env::WriteParam($oh, 'user home directory', userHome => ($ENV{HOME} || $ENV{HOMEPATH}));
    # Write the perl path. Note this is a forced override.
    Env::WriteParam($oh, 'perl execution path', perl_path => $Config{perlpath}, 1);
    ## Put new non-Shrub parameters here.
    # Now we need to build our directory lists. We start with the module base directory.
    Env::WriteLines($oh, "", "# code module base directory",
            "our \$mod_base = '$modBaseDir';");
    # Now we set up the directory and module lists.
    my @scripts = map { "$modules->{$_}/scripts" } @FIG_Config::modules;
    my @libs = map { "$modules->{$_}/lib" } @FIG_Config::modules;
    Env::WriteLines($oh, "", "# list of script directories",
            "our \@scripts = ('" . join("', '", @scripts) . "');",
            "",  "# list of PERL libraries",
            "our \@libs = ('" . join("', '", "$projDir/config", @libs) . "');",
            "", "# list of project modules",
            "our \@modules = qw(" . join(" ", @FIG_Config::modules) . ");",
            "", "# list of shared modules",
            "our \@shared = qw(" . join(" ", @FIG_Config::shared) . ");",
            "", "# list of java modules",
            "our \@java = qw(" . join(" ", @FIG_Config::java) . ");",
            );
    # Set up the tool directories.
    my $packages = "$FIG_Config::proj/packages";
    my @toolDirs;
    if (opendir(my $dh, $packages)) {
        my @dirs = grep { substr($_,0,1) ne '.' && -d "$packages/$_" } readdir($dh);
        print "Package directories found: " . join(", ", @dirs) . "\n";
        @toolDirs = map { "$_/bin" } grep { -d "$packages/$_/bin" } @dirs;
        push @toolDirs, grep { $_ =~ /^art_bin_/ && -f "$packages/$_/art_illumina" } @dirs;
    }
    Env::WriteLines($oh, "", "# list of tool directories",
            "our \@tools = (" . join(", ", map { "'$projDir/packages/$_'" } @toolDirs) .
                    ");");
    # Now comes the Shrub configuration section.
    my $userdata = $opt->dbuser . "/" . ($opt->dbpass // '');
    my $dbname = $opt->dbname // '';
    Env::WriteLines($oh, "", "", "# SHRUB CONFIGURATION", "");
    Env::WriteParam($oh, 'root directory for Shrub data files (should have subdirectories "Inputs" (optional) and "LoadFiles" (required))',
            data => $dataRootDir, $kbase);
    Env::WriteParam($oh, 'full name of the Shrub DBD XML file', shrub_dbd => "$modules->{ERDB}/ShrubDBD.xml", $kbase);
    Env::WriteParam($oh, 'Shrub database signon info (name/password)', userData => $userdata);
    Env::WriteParam($oh, 'name of the Shrub database (empty string to use the default)', shrubDB => $dbname);
    Env::WriteParam($oh, 'TRUE if we should create indexes before a table load (generally TRUE for MySQL, FALSE for PostGres)',
            preIndex => 1);
    Env::WriteParam($oh, 'default DBMS (currently only "mysql" works for sure)', dbms => "mysql");
    Env::WriteParam($oh, 'database access port', dbport => 3306);
    Env::WriteParam($oh, 'TRUE if we are using an old version of MySQL (legacy parameter; may go away)', mysql_v3 => 0);
    Env::WriteParam($oh, 'default MySQL storage engine', default_mysql_engine => "InnoDB");
    Env::WriteParam($oh, 'database host server (empty string to use the default)', dbhost => $opt->dbhost);
    Env::WriteParam($oh, 'TRUE to turn off size estimates during table creation-- should be FALSE for MyISAM',
            disable_dbkernel_size_estimates => 1);
    Env::WriteParam($oh, 'mode for LOAD TABLE INFILE statements, empty string is OK except in special cases (legacy parameter; may go away)',
            load_mode => '');
    # Now comes the DNA repository. There are two cases-- a local repository or a global one. Check the type.
    my $dnaRepo = $opt->dna;
    if (! $dnaRepo) {
        # Here we have the local repository.
        $dnaRepo = "$dataRootDir/DnaRepo";
    } elsif ($dnaRepo eq 'none') {
        $dnaRepo = '';
    }
    Env::WriteParam($oh, 'location of the DNA repository', shrub_dna => $dnaRepo, $kbase);
    # Next the sample repository. This is simpler.
    my $sampleRepo = "$dataRootDir/SampleRepo";
    Env::WriteParam($oh, 'location of the Sample repository (blank for none)', shrub_sample => $sampleRepo);
    ## Put new Shrub parameters here.
    if ($vanillaMode || $kbase) {
        # For a vanilla project or KBase, we need to convince FIG_Config to modify the path and the libpath.
        my @paths = ($winMode ? (@scripts) : "$FIG_Config::proj/bin");
        GeneratePathFix($oh, $winMode, scripts => 'PATH', @paths);
        # Do the same with PERL5LIB.
        GeneratePathFix($oh, $winMode, libraries => 'PERL5LIB', @libs, "$FIG_Config::proj/config");
    }
    if ($vanillaMode) {
        if (! $winMode) {
            # On the Mac, we need to fix the MySQL library path.
            opendir(my $dh, "/usr/local") || die "Could not perform MySQL directory search.";
            my ($libdir) = grep { ($_ =~ /^mysql-\d+/) && (-f "/usr/local/$_/libmysqlclient.18.dylib") } readdir $dh;
            if ($libdir) {
                Env::WriteLines($oh, "", "# Set DYLD path for mysql",
                        "\$ENV{DYLD_FALLBACK_LIBRARY_PATH} = \"/usr/local/$libdir/lib\";");
                print "\n**** NOTE: IF DBD::MySQL fails, you will need to run\n\n";
                print "sudo ln -s /usr/local/$libdir/lib/libmysqlclient.18.dylib /usr/local/lib/libmysqlclient.18.dylib\n\n";
            }
        } elsif ($winMode) {
            # On Windows, we need to upgrade that PATHEXT.
            Env::WriteLines($oh, "", "# Insure PERL is executable.",
                    "unless (\$ENV{PATHEXT} =~ /\.pl/i) {",
                    "    \$ENV{PATHEXT} .= ';.pl';",
                    "}");
            Env::WriteLines($oh, "", "# Insure PYTHON is executable.",
                    "unless (\$ENV{PATHEXT} =~ /\.py/i) {",
                    "    \$ENV{PATHEXT} .= ';.py';",
                    "}");
        }
    }
    if ($kbase) {
        # For a KBase project, we need to add the include libraries to @INC.
        Env::WriteLines($oh, "", "# Add include paths.", "push \@INC, '" . join("', '", @libs) . "';");
    }
    # Write the trailer.
    print $oh "\n1;\n";
    # Close the output file.
    close $oh;
}

=head3 GeneratePathFix

    GeneratePathFix($oh, $winMode, $type => $var, @paths);

Generate the FIG_Config PERL code to update an environment variable with new
path information. This is used for both the system search path and
the PERL module libraries.

=over 4

=item oh

Open output handle for the code lines generated.

=item winMode

TRUE if this is Windows, FALSE otherwise.

=item type

Type of thing being added to the environment variable value, plural, for comments.

=item var

Name of the environment variable being updated.

=item paths

List of the path elements to add to the environment variable.

=back

=cut

sub GeneratePathFix {
    # Get the parameters.
    my ($oh, $winMode, $type => $var, @paths) = @_;
    # Compute the delimiter.
    my $delim = ($winMode ? ';' : ':');
    # Create the string to add to the path.
    my $newPath = Env::BuildPathList($winMode, $delim, @paths);
    my $newPathLen = length($newPath);
    # Now we have the text and length of the new path string. Escape any backslashes
    # in the path string and convert it to a quoted string.
    $newPath =~ s/\\/\\\\/g;
    $newPath = '"' . $newPath . '"';
    # Append the code to fix the path.
    Env::WriteLines($oh, "",
        "# Insure the $var has our $type in it.",
        "\$_ = $newPath;",
        "if (! \$ENV{$var}) {",
        "    \$ENV{$var} = \$_;",
        "} elsif (substr(\$ENV{$var}, 0, $newPathLen) ne \$_) {",
        "    \$ENV{$var} = \"\$_$delim\$ENV{$var}\";",
        "}");
}

=head3 WriteAllConfigs

    WriteAllConfigs($winMode, \%modules, $projDir, $opt);

Write out the path and library configuration parameters for a
vanilla environment. This creates a C<user-env> file in the
project directory and optionally builds the C<.includepath> files for all
the Eclipse projects. The C<user-env> file is used in a
command shell to set up environment variables for PERL includes and
execution paths and switch to the Data directory.

This method presumes the B<FIG_Config> file has been updated and L</RunFigConfig> has
been called to load its variables.

=over 4

=item winMode

TRUE if we are in Windows, else FALSE.

=item modules

Reference to a hash mapping each module name to its directory on
disk.

=item projDir

Name of the project directory.

=item opt

Command-line options object.

=item oldenv

Reference to a hash that contains the original environment.

=back

=cut

sub WriteAllConfigs {
    # Get the parameters.
    my ($winMode, $modules, $projDir, $opt, $oldenv) = @_;
    # Compute the output file, the comment mark, and the path delimiter.
    my $fileName = "$projDir/user-env.";
    my ($delim, $rem);
    if ($winMode) {
        $fileName .= "cmd";
        $delim = ";";
        $rem = "REM ";
    } else {
        $fileName .= "sh";
        $delim = ":";
        $rem = "#";
    }
    # Open the output file.
    open(my $oh, ">$fileName") || die "Could not open shell configuration file $fileName: $!";
    # Do an ECHO OFF for Windows.
    if ($winMode) {
        print $oh "\@ECHO OFF\n";
    }
    print "Writing environment changes to $fileName.\n";
    #
    # Compute the script paths.
    my $paths = join($delim, @FIG_Config::scripts);
    # Write the comment.
    print $oh "$rem Add SEEDtk scripts to the execution path.\n";
    # Do the path update.
    if ($winMode) {
        # In Windows it's complicated, because variables at the command prompt are
        # double-interpolated and we can't use them safely. We have to use an
        # explicit path-- the current environment has the path we need already in it.
        $paths = "$ENV{PATH}";
        $paths =~ s/&/^&/g;
        # Check for the GitHub for Windows option.
        if ($opt->gfw) {
            $paths .= ';%localappdata%\GitHub\PORTAB~1\cmd'
        }
        # Add the project directory if we need it.
        my $projDirForPath = $projDir;
        $projDirForPath =~ tr/\//\\/;
        if (index($paths, $projDirForPath) < 0) {
            if (substr($paths, -1, 1) ne ';') {
                $paths .= ';';
            }
            $paths .= $projDirForPath;
        }
        print $oh "path $paths\n";
    } else {
        # On the Mac, we simply put the bin subdirectory in the path.
        print $oh "export PATH=$projDir/bin:\$PATH\n";
    }
    # Set the PERL libraries.
    my $libs = join($delim, @FIG_Config::libs);
    print $oh "$rem Add SEEDtk libraries to the PERL library path.\n";
    if ($ENV{PERL5LIB}) {
        # There are already libraries, so set this up as an append operation.
        $libs .= ($winMode ? ';%PERL5LIB%' : ':$PERL5LIB');
    }
    if ($winMode) {
        print $oh "SET PERL5LIB=$libs\n";
    } else {
        print $oh "export PERL5LIB=$libs\n";
    }
    # The libraries and the path are now set up.
    if ($winMode && $oldenv->{PATHEXT} !~ /.pl(?:;|$)/i) {
        # Here we are in Windows and PERL scripts are not set up as
        # an executable type. We need to fix that.
        print $oh "SET PATHEXT=%PATHEXT%;.PL\n"
    }
    # Add the environment variable that tells us what our environment is.
    if ($winMode) {
        print $oh "SET STK_TYPE=Windows\n";
        print $oh "SET SERVICE=SEEDtk\n";
    } else {
        print $oh "export STK_TYPE=Mac\n";
        print $oh "export SERVICE=SEEDtk\n";
    }
    # If the user wants a data directory switch, put it here.
    if ($FIG_Config::data_switch) {
        print $oh "cd $FIG_Config::data\n";
    }
    # Close the output file.
    close $oh;
    # If this is NOT Windows, fix the permissions.
    if (! $winMode) {
        chmod 0755, $fileName;
    }
    if ($eclipseMode) {
        # Now we need to create the includepath files. These are XML files that have
        # to appear in every project directory and specify from which other projects
        # it can include modules. In most cases this is all of them. The INCLUDES
        # hash specifies the exceptions.
        print "Writing includepath files.\n";
        for my $module (keys %$modules) {
            my $mh = IO::File->new(">$modules->{$module}/.includepath") ||
                    die "Could not open Eclipse includepath file for $module: $!";
            my $xmlOut = XML::Writer->new(OUTPUT => $mh, DATA_MODE => 1, DATA_INDENT => 4);
            $xmlOut->xmlDecl("UTF-8");
            # The main tag enclosing all others is "includepath".
            $xmlOut->startTag("includepath");
            # Determine the list of libraries.
            my $libList;
            if (INCLUDES->{$module}) {
                $libList = INCLUDES->{$module};
            } else {
                $libList = \@FIG_Config::modules;
            }
            # Include the project directory for FIG_Config.
            $xmlOut->emptyTag('includepathentry', path => File::Spec->rel2abs("$projDir/config"));
            # Loop through the paths, generating includepathentry tags.
            for my $lib (@$libList) {
                $xmlOut->emptyTag('includepathentry', path => File::Spec->rel2abs("$modules->{$lib}/lib"));
            }
            # Close the main tag.
            $xmlOut->endTag("includepath");
            # Close the document.
            $xmlOut->end();
        }
    }
}


=head3 BuildPaths

    BuildPaths($winmode, $label => $rootDir, @subdirs);

Create the desired subdirectories for the specified root directory. The
type of root directory is provided as a label for status messages. On
Unix systems, a C<chmod> will be performed to fix the privileges.

=over 4

=item winmode

TRUE for a Windows system, FALSE for a Unix system.

=item label

Label describing the type of directory being created.

=item rootDir

Root directory path. All new paths created will be under this one.

=item subdirs

List of path names, relative to the specified root directory, that we
must insure exist.

=back

=cut

sub BuildPaths {
    # Get the parameters.
    my ($winmode, $label, $rootDir, @subdirs) = @_;
    # Loop through the new paths.
    for my $path (@subdirs) {
        my $newPath = "$rootDir/$path";
        # Check to see if the directory is already there.
        if (! -d $newPath) {
            # No, we must create it.
            File::Path::make_path($newPath);
            print "$label directory $newPath created.\n";
            # If this is Unix, fix the permissions.
            if (! $winmode) {
                chmod 0777, $newPath;
            }
        }
    }
}


=head3 FixPath

    my $absPath = FixPath($path);

Convert a path from relative to absolute, convert backslashes to slashes, and remove the drive letter.
This makes the path suitable for passing around in PERL.

=over 4

=item path

Path to convert.

=item RETURN

Returna an absolute, canonical version of the path.

=back

=cut

sub FixPath {
    # Get the parameters.
    my ($path) = @_;
    # Convert the path to a canonical absolute.
    my $retVal = File::Spec->rel2abs($path);
    # Convert backslashes to slashes.
    $retVal =~ tr#\\#/#;
    # Remove the drive letter (if any).
    $retVal =~ s/^\w://;
    # Return the result.
    return $retVal;
}


=head3 SetupBinaries

    SetupBinaries($projDir, \%modules, $opt);

Create the bin directory (if needed) and insure all the scripts have
executable wrappers. This is only needed for the vanilla environment on
the Mac. Wrappers are unnecessary in Windows, and a different mechanism
exists for the wrappers in non-vanilla Unix.

=over 4

=item projDir

The path to the project directory. The C<bin> directory is put in here.

=item modules

Reference to a hash that maps each module name to its directory. The
scripts are all in the C<scripts> subdirectories of the module
directories.

=item opt

The command-line options from the configuration script.

=back

=cut

sub SetupBinaries {
    # Get the parameters.
    my ($projDir, $modules, $opt) = @_;
    # Insure we have a bin directory.
    my $binDir = "$projDir/bin";
    if (! -d $binDir) {
        File::Path::make_path($binDir);
        print "$binDir created.\n";
    }
    # This will contain a list of the wrappers we create. We prime it with our system
    # script names.
    my %wrappers = ('pull-all' => 1);
    # Loop through the modules.
    for my $module (keys %$modules) {
        # Get the scripts for this module.
        my $scriptDir = "$modules->{$module}/scripts";
        opendir(my $dh, $scriptDir) || die "Could not open script directory $scriptDir: $!";
        my @scripts = grep { $_ =~ /\.(?:pl|sh|py)$/i } readdir($dh);
        closedir $dh;
        # Loop through them, creating the wrappers.
        for my $script (@scripts) {
            SetupScript($script, $binDir, $scriptDir, \%wrappers);
        }
        # Create the Config script.
        SetupScript('Config.pl', $binDir, $projDir, \%wrappers);
    }
    # Now delete the obsolete wrappers.
    opendir(my $dh, $binDir) || die "Could not open binary directory $binDir: $!";
    my @badBins = grep { substr($_,0,1) ne '.' && -f "$binDir/$_" && ! $wrappers{$_} } readdir($dh);
    closedir $dh;
    for my $badBin (@badBins) {
        unlink("$binDir/$badBin");
        print "Obsolete script $badBin deleted.\n";
    }
}

=head3 SetupJava

    SetupJava($kernelBase, $projDir);

Handle the commands for executing the jar targets.

=over 4

=item jarBase

The base directory for the jar files.

=item projDir

The SEEDtk project directory.

=back

=cut

sub SetupJava {
    my ($jarBase, $projDir) = @_;
    if (opendir(my $dh, $jarBase)) {
        # Find the jar files.
        my @jars = grep { $_ =~ /\.jar$/ } readdir $dh;
        closedir $dh;
        for my $jarFile (@jars) {
            # Extract the jar name.
            if ($jarFile =~ /(.+)\.jar/) {
                my $javaName = $1;
                # Check for a parm file.
                my $parms = "";
                if (open(my $ph, '<', "$jarBase/$javaName.txt")) {
                    $parms = <$ph>;
                    chomp $parms;
                    close $ph;
                }
                print "Building java command $javaName.\n";
                my $command = "java $parms -jar $jarBase/$jarFile";
                # Create the appropriate executable file.
                if ($winMode) {
                    open(my $jh, '>', "$projDir/$javaName.cmd") || die "Could not open $javaName command file: $!";
                    print $jh "\@echo off\n";
                    print $jh "$command \%\*\n";
                    close $jh;
                } else {
                    open(my $jh, '>', "$projDir/bin/$javaName") || die "Could not open $javaName command file: $!";
                    print $jh "$command \$\@\n";
                    close $jh;
                    chmod 0x755, "$projDir/bin/$javaName";
                }
            }
        }
    }
}

=head3 SetupCommands

    SetupCommands(\%modules, $opt);

Create DOS versions of all the bash shell scripts in the module
directories. This involves creating a file with a CMD extension, changing
the continuation characters from C<\> to C<^>, and changing the parameter
marks from $n to %n.

=over 4

=item modules

Reference to a hash that maps each module name to its directory. The
shell scripts are all in the C<scripts> subdirectories of the module
directories.

=item opt

The command-line options from the configuration script.

=back

=cut

sub SetupCommands {
    # Get the parameters.
    my ($modules, $opt) = @_;
    # Loop through the modules.
    for my $module (keys %$modules) {
        # Get the scripts for this module.
        my $scriptDir = "$modules->{$module}/scripts";
        opendir(my $dh, $scriptDir) || die "Could not open script directory $scriptDir: $!";
        my @scripts = grep { $_ =~ /\.sh$/i } readdir($dh);
        closedir $dh;
        # Loop through the shell scripts found.
        for my $script (@scripts) {
            # Open this script for input.
            open(my $ih, "<$scriptDir/$script") || die "Could not open script file $script: $!";
            # Open the corresponding command file for output.
            my $outFile = $script;
            $outFile =~ s/\.sh$/.cmd/;
            open(my $oh, ">$scriptDir/$outFile") || die "Could not open output file $outFile: $!";
            # Turn off echoing.
            print $oh "\@echo off\n";
            # Loop through the input.
            while (! eof $ih) {
                my $line = <$ih>;
                # Translate the continuation character.
                if ($line =~ /(.+)\\$/) {
                    $line = "$1^\n";
                }
                # Translate variable markers.
                $line =~ s/\$(\d+)/%$1/g;
                $line =~ s/\$\@/%*/g;
                # Write the line.
                print $oh $line;
            }
            # Close the output file.
            close $oh;
            print "Script $outFile created.\n";
        }
    }
}


=head3 SetupCGIs

    SetupCGIs($webdir, $opt);

Fix the permissions on the CGI scripts. This is only needed for the vanilla
environment on the Mac.

=over 4

=item webdir

The path to the web directory. The CGI scripts are in this directory.

=item opt

The command-line options from the configuration script.

=back

=cut

sub SetupCGIs {
    # Get the parameters.
    my ($webdir, $opt) = @_;
    # Only proceed if we have a web directory.
    if (-d $webdir) {
        # Get the CGI scripts.
        opendir(my $dh, $webdir) || die "Could not open web directory $webdir.";
        my @scripts = grep { substr($_, -4, 4) eq '.cgi' } readdir($dh);
        closedir $dh;
        # Loop through them, setting permissions.
        for my $script (@scripts) {
            # Compute the file name.
            my $fileName = "$webdir/$script";
            # Turn on the execution bits.
            my @finfo = stat $fileName;
            my $newMode = ($finfo[2] & 0777) | 0111;
            chmod $newMode, $fileName;
        }
        print "CGI permissions set.\n";
    }
}

sub SetupScript {
    my ($script, $binDir, $scriptDir, $wrappers) = @_;
    # Get the unsuffixed script name and the suffix.
    my ($binaryName, $type) = $script =~ /(.+)\.(.+)/;
    # Create the wrapper file.
    my $fileName = "$binDir/$binaryName";
    open(my $oh, ">$fileName") || die "Could not open $binaryName: $!";
    print $oh "#!/usr/bin/env bash\n";
    if ($type eq 'pl') {
        # For PERL, we ask perl to execute the file.
        print $oh "perl $scriptDir/$script \"\$\@\"\n";
    } elsif ($type eq 'py') {
        # For PYTHON, we ask python to execute the file.
        print $oh "python $scriptDir/$script \"\$\@\"\n";
    } elsif ($type eq 'sh') {
        # For bash, we execute the file directly. This requires updating permissions.
        print $oh "$scriptDir/$script \"\$\@\"\n";
        chmod 0x755, "$scriptDir/$script";
    } else {
        die "Invalid script suffix $type found in $scriptDir.\n";
    }
    close $oh;
    # Turn on the execution bits.
    my @finfo = stat $fileName;
    my $newMode = ($finfo[2] & 0777) | 0111;
    chmod $newMode, $fileName;
    # Denote we created this file.
    if ($wrappers) {
        $wrappers->{$binaryName} = 1;
    }
}
