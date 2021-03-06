#
#   MailWatch for MailScanner Custom Module SQLSpamSettings
#
#   $Id: SQLSpamSettings.pm,v 1.4 2011/12/14 18:21:28 lorodoes Exp $
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

#
# This module uses entries in the user table to determine the Spam Settings
# for each user.
#

package MailScanner::CustomConfig;

use strict 'vars';
use strict 'refs';
no  strict 'subs'; # Allow bare words for parameter %'s

use vars qw($VERSION);

### The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = substr q$Revision: 1.4 $, 10;

use DBI;
my(%LowSpamScores, %HighSpamScores);
my(%ScanList);
my($db_name) = 'mailscanner';
my($db_host) = 'localhost';
my($db_user) = 'mailwatch';
my($db_pass) = 'mailwatch';

#
# Initialise the arrays with the users Spam settings
#
sub InitSQLSpamScores
{
  my($entries) = CreateScoreList('spamscore', \%LowSpamScores);
  MailScanner::Log::InfoLog("Read %d Spam entries", $entries);
}

sub InitSQLHighSpamScores
{
  my $entries = CreateScoreList('highspamscore', \%HighSpamScores);
  MailScanner::Log::InfoLog("Read %d high Spam entries", $entries);
}

sub InitSQLNoScan
{
  my $entries = CreateNoScanList('noscan', \%ScanList);
  MailScanner::Log::InfoLog("Read %d No Spam Scan entries", $entries);
}

#
# Lookup a users Spam settings
#
sub SQLSpamScores
{
  my($message) = @_;
  my($score)   = LookupScoreList($message, \%LowSpamScores);
  return $score;
}

sub SQLHighSpamScores
{
  my($message) = @_;
  my($score)   = LookupScoreList($message, \%HighSpamScores);
  return $score;
}

sub SQLNoScan
{
  my($message) = @_;
  my($noscan)  = LookupNoScanList($message, \%ScanList);
# MailScanner::Log::InfoLog("Returning %d from SQLNoScan", $noscan);
  return $noscan;
}

#
# Close down Spam Settings lists
#
sub EndSQLSpamScores
{
  MailScanner::Log::InfoLog("Closing down SQL Spam Scores");
}

sub EndSQLHighSpamScores
{
  MailScanner::Log::InfoLog("Closing down SQL High Spam Scores");
}

sub EndSQLNoScan
{
  MailScanner::Log::InfoLog("Closing down SQL No Scan");
}

# Read the list of users that have defined their own Spam Score value. Also
# read the domain defaults and the system defaults (defined by the admin user).
sub CreateScoreList
{
  my($type, $UserList) = @_;

  my($dbh, $sth, $sql, $username, $count);

  # Connect to the database
  $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host", $db_user, $db_pass, {PrintError => 0});

  # Check if connection was successfull - if it isn't
  # then generate a warning and return to MailScanner so it can continue processing.
  if (!$dbh)
  {
    MailScanner::Log::InfoLog("SQLSpamSettings::CreateList Unable to initialise database connection: %s", $DBI::errstr);
    return;
  }

  $sql = "SELECT username, $type FROM users WHERE $type > 0";
  $sth = $dbh->prepare($sql);
  $sth->execute;
  $sth->bind_columns(undef, \$username, \$type);
  $count = 0;
  while($sth->fetch())
  {
    $UserList->{lc($username)} = $type; # Store entry
    $count++;
  }

  # Close connections
  $sth->finish();
  $dbh->disconnect();

  return $count;
}

# Read the list of users that have defined that don't want Spam scanning.
sub CreateNoScanList
{
  my($type, $NoScanList) = @_;

  my($dbh, $sth, $sql, $username, $count);

  # Connect to the database
  $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host", $db_user, $db_pass, {PrintError => 0});

  # Check if connection was successfull - if it isn't
  # then generate a warning and return to MailScanner so it can continue processing.
  if (!$dbh)
  {
    MailScanner::Log::InfoLog("SQLSpamSettings::CreateNoScanList Unable to initialise database connection: %s", $DBI::errstr);
    return;
  }

  $sql = "SELECT username, $type FROM users WHERE $type > 0";
  $sth = $dbh->prepare($sql);
  $sth->execute;
  $sth->bind_columns(undef, \$username, \$type);
  $count = 0;
  while($sth->fetch())
  {
    $NoScanList->{lc($username)} = 1; # Store entry
    $count++;
  }

  # Close connections
  $sth->finish();
  $dbh->disconnect();

  return $count;
}

# Based on the address it is going to, choose the correct Spam score.
# If the actual "To:" user is not found, then use the domain defaults
# as supplied by the domain administrator. If there is no domain default
# then fallback to the system default as defined in the "admin" user.
# If the user has not supplied a value and the domain administrator has
# not supplied a value and the system administrator has not supplied a
# value, then return 999 which will effectively let everything through
# and nothing will be considered Spam.
#
sub LookupScoreList
{
  my($message, $LowHigh) = @_;

  return 0 unless $message; # Sanity check the input

  # Find the first "to" address and the "to domain"
  my(@todomain, $todomain, @to, $to);
  @todomain   = @{$message->{todomain}};
  $todomain   = $todomain[0];
  @to         = @{$message->{to}};
  $to         = $to[0];

  # It is in the list with the exact address? if not found, get the domain,
  # if that's not found,  get the system default otherwise return a high
  # value to just let the email through.
  return $LowHigh->{$to}       if $LowHigh->{$to};
  return $LowHigh->{$todomain} if $LowHigh->{$todomain};
  return $LowHigh->{"admin"}   if $LowHigh->{"admin"};

  # There are no Spam scores to return if we made it this far, so let the email through.
  return 999;
}

# Based on the address it is going to, decide whether or not to scan.
# the users email for Spam.
sub LookupNoScanList
{
  my($message, $NoScan) = @_;

  return 0 unless $message; # Sanity check the input

  # Find the first "to" address and the "to domain"
  my(@todomain, $todomain, @to, $to);
  @todomain   = @{$message->{todomain}};
  $todomain   = $todomain[0];
  @to         = @{$message->{to}};
  $to         = $to[0];

  # It is in the list with the exact address? if not found, get the domain,
  # if that's not found, return 0
  return 0 if $NoScan->{$to};
  return 0 if $NoScan->{$todomain};

  # There is no setting, then go ahead and scan for Spam, be on the safe side.
  return 1;
}

1;
