#!/usr/bin/env raku

use lib '/home/mdevine/github.com/raku-REST-Client-Role/lib';
use ISP::dsmadmc;
use REST::Client;
use Cro::Uri;

use Data::Dump::Tree;

#   my @redis-servers;
#   if "$*HOME/.redis-servers".IO.f {
#       @redis-servers = slurp("$*HOME/.redis-servers").chomp.split("\n");
#   }
#   else {
#       die 'Unable to initialized without ~/.redis-servers';
#   }
#   my @redis-clis;
#   for @redis-servers -> $redis-server {
#       my @cmd-string = sprintf("ssh -L 127.0.0.1:6379:%s:6379 %s /usr/bin/redis-cli", $redis-server, $redis-server).split: /\s+/;
#       @redis-clis.push: @cmd-string;
#   }
#   for @redis-clis -> @redis-cli {
#       my @rcmd        = flat @redis-cli,
#                       '--raw',
#                       'KEYS',
#                       $isp-server-REDIS-keys-base ~ ':*';
#       my $proc        = run   @rcmd, :out, :err;
#       my $out         = $proc.out.slurp(:close);
#       my $err         = $proc.err.slurp(:close);
#       fail 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
#       if $out {
#           my @ispssks = $out.chomp.split("\n");
#           die "No ISP server site keys!" unless @ispssks;
#           @rcmd   = flat @redis-cli,
#                   '--raw',
#                   'SUNION',
#                   @ispssks.join: ' ';
#           $proc    = run   @rcmd, :out, :err;
#           $out     = $proc.out.slurp(:close);
#           $err     = $proc.err.slurp(:close);
#           die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
#           if $out {
#               %!isp-servers = $out.chomp.split("\n").map: { $_.uc => {} };
#               die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & install '/usr/bin/dsmadmc' on this host." unless '/opt/tivoli/tsm/client/ba/bin/dsm.sys'.IO.path:s;
#               my @dsm-sys     = slurp('/opt/tivoli/tsm/client/ba/bin/dsm.sys').lines;
#               my $current-server;
#               my $current-client;
#               for @dsm-sys -> $rcd {
#                   if $rcd ~~ m:i/ ^ SERVERNAME \s+ $<client>=(<alnum>+?) '_' $<server>=(<alnum>+) \s* $ / {           # %%% make this accept client names with '_'; take all but not the last '_'
#                       $current-server = $/<server>.Str;
#                       $current-client = $/<client>.Str;
#                       %!isp-servers{$current-server}{$current-client} = ISP-SERVER-INFO.new(:SERVERNAME($current-client ~ '_' ~ $current-server));
#                   }
#                   elsif $rcd ~~ m:i/ ^ \s* TCPS\w* \s+ $<value>=(.+) \s* $/ {
#                       %!isp-servers{$current-server}{$current-client}.TCPSERVERADDRESS = $/<value>.Str;
#                   }
#               }
#               return self;
#           }
#       }
#   }
#   unless %!isp-servers.elems {
#       $*ERR.put: colored('No ISP Servers defined in Redis under ' ~ $isp-server-REDIS-keys-base ~ ' keys!', 'red');
#       die colored('Either fix your --$isp-server=<value> or update Redis ' ~ $isp-server-REDIS-keys-base ~ ':*', 'red');
#   }

my $user-id         =   'WMATA\tsmadmin';
my $user-id-sterile = $user-id.subst('\\', '_');

my @nfs-queries     =   'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/nfs/exports',
                        'https://jgdciisln01nfs.wmataisln.local:8080/platform/1/protocols/nfs/exports',
                        'https://ctdciisln01nfs.wmataisln.local:8080/platform/1/protocols/nfs/exports';

my @smb-queries     =   'https://jgctsmb.wmataisln.local:8080/platform/1/protocols/smb/shares',
                        'https://vdismb.wmataisln.local:8080/platform/1/protocols/smb/shares';
#                       'https://jgctnfs.wmataisln.local:8080/platform/1/protocols/smb/shares';

class Isilon-Rest-Client does REST::Client {}

my $stash-path;

sub MAIN (
    Str:D   :$isp-server!,                      #= ISP server name (SELECT SERVER_NAME FROM STATUS)
    Str:D   :$isp-admin!,                       #= ISP server Admin account
    Bool    :$nfs,                              #= list NFS shares
    Bool    :$smb,                              #= list SMB shares
    ) {
    my $rest-client;

    my ISP::dsmadmc $dsmadmc   .= new(:$isp-server, :$isp-admin);

    if $nfs {
        my %nfs-nodes;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%NFS%'"]) -> $node-record {
            %nfs-nodes{$node-record<NODE_NAME>} = 1;
        }
#ddt %nfs-nodes;
#die;
        for @nfs-queries -> $url {
            my $user-id-sterile = $user-id.subst('\\', '_');
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ Cro::Uri.parse($url).host ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:$url, :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<exports>.list -> $export {
                for $export<paths>.list -> $path {
                    printf "%s", $path;
                    if $path ~~ /^ \/ifs\/j / {
                        put "\tP_";
                    }
                }
            }
        }
    }
    elsif $smb {
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%SMB%'"]) -> $node-record {
            put $node-record<NODE_NAME>;
        }
die;
        for @smb-queries -> $url {
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ Cro::Uri.parse($url).host ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:$url, :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<shares>.list -> $share {
                printf "%-30s%s\n", $share<name>, $share<path>;
            }
        }
    }
    else {
        die $*USAGE;
    }
}

=finish

curl https://jgctnfs.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctnfs.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctsmb.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://jgctsmb.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
curl https://vdismb.wmataisln.local:8080/platform/1/protocols/smb/shares --insecure --basic --user wmata\\tsmadmin:${PASSWD}
#curl https://vdismb.wmataisln.local:8080/platform/1/protocols/nfs/exports --insecure --basic --user wmata\\tsmadmin:${PASSWD}
