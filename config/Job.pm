#
# Copyright (c) 2003-2015 University of Chicago and Fellowship
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


package Job;

    use strict;
    use warnings;
    use Config;
    use Data::UUID;
    use Getopt::Long::Descriptive;
    use FIG_Config;
    use File::Copy::Recursive;

=head1 Web Job Management

This object manages an Alexa background job. Each job is assigned a UUID, and its status is stored in
a file with the name C<Job.>I<UUID>C<.status>. The status file contains the following items, tab-separated.

=over 4

=item *

A task name, assigned by the object client.

=item *

The UUID of the job.

=item *

The process ID of the job.

=item *

The job status-- C<running>, C<completed>, C<failed>, or C<informed>.

=item *

A status message from the job.

=back

The job must create this object when it starts and call the L</Fail> method when it fails or the L</Finish> method when it
terminates normally. It can call the L</Progress> method to record progress. It cannot use STDOUT, STDERR, or STDIN.
Web tasks can use the static L</Check> method to check the status of jobs in progress, Any with the C<completed> or C<failed>
status will be reported, and the status changed to C<informed>.

The static L</Purge> method can be used to remove all jobs with status C<informed>. This should be done periodically to avoid
performance problems with L</Check>.

The static L</Create> method is used to create the job.

Each job is assigned a private directory under the session directory with the
same name as the job's UUID. The L</workDir> method of this object returns the job's working directory and the
L</opt> method returns the L<Getopt::Long::Descriptive::Opts> method for accessing the command-line options.

This object contains the following fields.

=over 4

=item workDir

The name of the working directory for the job.

=item statusFile

The name of the job's status file.

=item UUID

The job's ID.

=item pid

The job's process ID.

=item taskName

The job's task name.

=item opt

The L<Getopt::Long::Descriptive::Opts> object for the command-line options.

=item status

The current status of the job (C<running>, C<failed>, C<completed>, or C<informed>).

=item comment

The last comment about the job's progress and/or status.

=back

=head2 Static Methods for Web Interface

=head3 Create

    my $pid = Job::Create($sessionDir, $name, $command, @parms);

Create a new job.

=over 4

=item sessionDir

The name of the session directory to contain the working files of the job.

=item name

The user-friendly name of the job.

=item command

The command to execute (without the C<.pl> suffix). It must be a script in the SEEDtk script libraries.

=item parms

A list of the job's parameters.

=item RETURN

Returns the process ID of the job created (on Windows) or 0 (on Unix/Mac).

=back

=cut

sub Create {
    my ($sessionDir, $name, $command, @parms) = @_;
    my $retVal;
    # Find the script.
    my ($dir) = grep { -f "$_/$command.pl" } @FIG_Config::scripts;
    if (! $dir) {
        die "Could not find command $command.";
    } else {
        # Compute a UUID.
        my $uuidObj = Data::UUID->new;
        my $uuid = $uuidObj->create_str();
        # Compute the status file name.
        my $statusFile = "$sessionDir/Job.$uuid.status";
        # Create the work directory.
        my $workDir = "$sessionDir/$uuid";
        if (! -d $workDir) {
            # Create the work directory.
            mkdir $workDir, 0777;
        }
        print "Working directory is $workDir.\n";
        print "Command found in $dir.\n";
        # Get the perl path.
        # Push the necessary communication parameters onto the parameter list.
        my @finalParms = ("--uuid=$uuid", "--name=\"$name\"", "--workDir=\"$workDir\"", "--statusFile=\"$statusFile\"", @parms);
        # Create the job. The job itself will create the status file.
        if ($FIG_Config::win_mode) {
            $retVal = system(1, 'perl', "$dir/$command.pl", @finalParms);
        } else {
            $retVal = fork;
            if ($retVal) {
                print "Process ID is $retVal.\n";
            } elsif (defined $retVal) {
                exec("/usr/bin/env", "perl", "-I$FIG_Config::proj/config", "$dir/$command.pl", @finalParms)
                    || die "Failed to execute $command: $!";
            } else {
                die "Could not create job for $command: $!";
            }
#            my $rc = system(join(' ', "perl -I $FIG_Config::proj/config $dir/$command.pl", @finalParms, '&'));
#            if ($rc) {
#                print "Command failed with return value $rc.\n";
#            }
        }
    }
    return $retVal;
}

=head3 Check

    my $statusList = Job::Check($sessionDir, $complete);

Return a list of all the jobs in the session directory that have completed or failed since the last check.

=over 4

=item sessionDir

The name of the session directory containing the job status files.

=item complete

If TRUE, all jobs will be reported. If FALSE, only completed jobs.

=item RETURN

Returns a reference to a list of statements about the updated jobs.

=back

=cut

use constant STATUS_VERB => { running => 'is', terminated => 'was', informed => 'is' };

sub Check {
    my ($sessionDir, $complete) = @_;
    # This will be the return list.
    my @retVal;
    # This will count the open failures.
    my $failCount = 0;
    # Get all the job status files.
    my $jobsL = GetJobFiles($sessionDir);
    for my $job (@$jobsL) {
        # Get the job status.
        my $jobObject = Job->new_from_file($sessionDir, $job);
        my $status = $jobObject->{status};
        my $comment = $jobObject->{comment};
        if ($status ne 'informed') {
            if ($status eq 'running') {
                # Verify the job is still running.
                my $pid = $jobObject->{pid};
                my $rc = kill(0, $pid);
                # If it is not running, it terminated.
                if (! $rc) {
                    $status = 'terminated';
                }
            }
            my $phrase = STATUS_VERB->{$status} // 'has';
            if ($status ne 'running' || $complete) {
                push @retVal, "$jobObject->{taskName} $phrase $status: $comment";
            }
            if ($status ne 'running') {
                $jobObject->UpdateStatus('informed', $comment);
            }
        }
    }
    # Return the list of messages.
    return \@retVal;
}

=head3 Purge

    my $count = Job::Purge($sessionDir);

Purge all jobs with a status of C<informed> from the session directory.

=over 4

=item sessionDir

The session directory containing the jobs.

=item RETURN

Returns the number of jobs purged.

=back

=cut

sub Purge {
    my ($sessionDir) = @_;
    # This will count the jobs purged.
    my $retVal = 0;
    # Get the list of job status files.
    my $jobList = GetJobFiles($sessionDir);
    # Loop through them.
    for my $job (@$jobList) {
        my $jobObject = Job->new_from_file($sessionDir, $job);
        if ($jobObject->{status} eq 'informed') {
            unlink $jobObject->{statusFile};
            File::Copy::Recursive::pathrmdir($jobObject->workDir);
            $retVal++;
        }
    }
    # Return the count.
    return $retVal;
}

=head2 Static Internal Methods

=head3 GetJobFiles

    my $fileNameList = Job::GetJobFiles($sessionDir);

Return a list of the job status files in the specified directory.

=over 4

=item sessionDir

Session directory containing job status files.

=item RETURN

Returns a reference to a list of the file names (not including the directoy path).

=back

=cut

sub GetJobFiles {
    my ($sessionDir) = @_;
    opendir(my $dh, $sessionDir) || die "Could not read session directory: $!";
    my @retVal = grep { $_ =~ /^Job\.[A-F0-9\-]+\.status$/ } readdir $dh;
    return \@retVal;
}

=head2 Special Methods

=head3 new

    my $jobObject = $jobObject->new($parmComment, @options);

Initialize the current job. This method is called from within the command script.

=over 4

=item parmComment

The comment describing the positional parameters.

=item options

The L<Getopt::Long::Descriptive> descriptors for the command-line options.

=item RETURN

Returns a L</Job Object> containing information about the job.

=back

=cut

sub new {
    my ($class, $parmComment, @options) = @_;
    # Parse the command line.
    my ($opt, $usage) = describe_options("%c %o $parmComment",
            ['uuid=s', 'global unique ID string for this job', { required => 1 }],
            ['name=s', 'name of this job', { required => 1 }],
            ['statusFile=s', 'name of the job status file', { required => 1 }],
            ['workDir=s', 'name of the job work directory', { required => 1 }],
            @options,
           [ "help|h", "display usage information", { shortcircuit => 1}]);
    # The above method dies if the options are invalid. We check here for the HELP option.
    if ($opt->help) {
        print $usage->text;
        exit;
    }
    # Here we are ready to run. Get the job object fields.
    my $uuid = $opt->uuid;
    my $workDir = $opt->workdir;
    my $statusFile = $opt->statusfile;
    my $taskName = $opt->name;
    # Compute the status.
    my $status = 'running';
    my $comment = "$0 command started.";
    # Create the object.
    my $retVal = {
        workDir => $workDir,
        statusFile => $statusFile,
        UUID => $uuid,
        pid => $$,
        opt => $opt,
        taskName => $taskName,
        status => $status,
        comment => $comment,
    };
    # Create the status file.
    UpdateStatus($retVal, $status, $comment);
    # Close the standard I/O streams to release the original job.
    close(STDIN); close(STDOUT); close(STDERR);
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}

=head3 new_from_file

    my $jobObject = Job->new_from_file($sessionDir, $statusFile);

Create a job object for an external job from its status file. This is a crippled version of the object that
will not have an L</opt> member.

=over 4

=item sessionDir

Session directory containing the status file.

=item statusFile

Name of the status file.

=back

=cut

sub new_from_file {
    my ($class, $sessionDir, $statusFile) = @_;
    # Read the status file.
    open(my $ih, '<', "$sessionDir/$statusFile") || die "Could not open job file $statusFile: $!";
    my $line = <$ih>;
    die "Job file $statusFile is empty." if ! $line;
    my ($taskName, $uuid, $pid, $status, $comment) = split "\t", $line;
    # Create the object.
    my $retVal = {
        workDir => "$sessionDir/$uuid",
        statusFile => "$sessionDir/$statusFile",
        UUID => $uuid,
        pid => $pid,
        taskName => $taskName,
        status => $status,
        comment => $comment
    };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}

=head2 Public Methods

=head3 Progress

    $jobObject->Progress($jobObject, $comment);

Denote that the job is making progress.

=over 4

=item jobObject

The L</Job Object> for the current job.

=item comment

A comment to place in the status file denoting the degree of progress.

=back

=cut

sub Progress {
    my ($self, $comment) = @_;
    $self->UpdateStatus('running', $comment);
}

=head3 Fail

    $jobObject->Fail($comment);

Denote that the job has failed.

=over 4

=item jobObject

The L</Job Object> for the current job.

=item comment

A comment to place in the status file denoting the type of failure.

=back

=cut

sub Fail {
    my ($self, $comment) = @_;
    $self->UpdateStatus('failed', $comment);
}

=head3 Finish

    $jobObject->Finish($jobObject, $comment);

Denote that the job has finished.


=over 4

=item jobObject

The L</Job Object> for the current job.

=item comment

A comment to place in the status file regarding the completion.

=back

=cut

sub Finish {
    my ($self, $comment) = @_;
    $self->UpdateStatus('completed', $comment);
}

=head3 statusFile

    my $fileName = $jobObject->statusFile;

Return the name of the job's status file.

=cut

sub statusFile {
    my ($self) = @_;
    return $self->{statusFile};
}

=head3 workDir

    my $dirName = $jobObject->workDir;

Return the name of the job's working directory.

=cut

sub workDir {
    my ($self) = @_;
    return $self->{workDir};
}

=head3 opt

    my $opts = $jobObject->opt;

Return the L<Getopt::Long::Descriptive> object for the command-line options of this job.

=cut

sub opt {
    my ($self) = @_;
    return $self->{opt};
}

=head2 Private Object Methods

=head3 UpdateStatus

    $jobObject->UpdateStatus($newStatus, $comment);

Update the status of this job and include a comment.

=over 4

=item newStatus

New job status-- C<running>, C<completed>, or C<informed>.

=item comment

Comment to place in the status file.

=back

=cut

sub UpdateStatus {
    my ($self, $newStatus, $comment) = @_;
    # Open and write the file.
    if (open(my $oh, '>', $self->{statusFile})) {
        print $oh join("\t", $self->{taskName}, $self->{UUID}, $self->{pid}, $newStatus, $comment);
        close $oh;
    } else {
        die "Job status file open failed: $!";
    }
}



1;