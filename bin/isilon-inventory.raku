#!/usr/bin/env raku

use ISP::dsmadmc;
use REST::Client;

use Data::Dump::Tree;

constant    $redis-service-account-key  = 'eb:isilon:service-account';
constant    $redis-nfs-authorities-key  = 'eb:isilon:nfs:authorities';
constant    $redis-smb-authorities-key  = 'eb:isilon:smb:authorities';

my $user-id;
my $user-id-sterile;
my @nfs-authorities;
my @smb-authorities;

sub get-config {
    my @redis-servers;
    if "$*HOME/.redis-servers".IO.f {
        @redis-servers = slurp("$*HOME/.redis-servers").chomp.split("\n");
    }
    else {
        die 'Unable to initialized without ~/.redis-servers';
    }
    my @redis-clis;
    for @redis-servers -> $redis-server {
        my @cmd-string = sprintf("ssh -L 127.0.0.1:6379:%s:6379 %s /usr/bin/redis-cli", $redis-server, $redis-server).split: /\s+/;
        @redis-clis.push: @cmd-string;
    }
    for @redis-clis -> @redis-cli {
        my @rcmd                = flat @redis-cli,
                                '--raw',
                                'GET',
                                $redis-service-account-key;
        my $proc                = run   @rcmd, :out, :err;
        my $out                 = $proc.out.slurp(:close);
        my $err                 = $proc.err.slurp(:close);
        die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
        if $out {
            $user-id            = $out.chomp;
            $user-id-sterile    = $user-id.subst('\\', '_');
        }
        else {
            die $err;
        }
    }
    for @redis-clis -> @redis-cli {
        my @rcmd                = flat @redis-cli,
                                '--raw',
                                'SMEMBERS',
                                $redis-nfs-authorities-key;
        my $proc                = run   @rcmd, :out, :err;
        my $out                 = $proc.out.slurp(:close);
        my $err                 = $proc.err.slurp(:close);
        die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
        if $out {
            @nfs-authorities    = $out.chomp.split(/\s+/);
            last if @nfs-authorities.elems;
        }
        else {
            die $err;
        }
    }
    for @redis-clis -> @redis-cli {
        my @rcmd                = flat @redis-cli,
                                '--raw',
                                'SMEMBERS',
                                $redis-smb-authorities-key;
        my $proc                = run   @rcmd, :out, :err;
        my $out                 = $proc.out.slurp(:close);
        my $err                 = $proc.err.slurp(:close);
        die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
        if $out {
            @smb-authorities    = $out.chomp.split(/\s+/);
            last if @smb-authorities.elems;
        }
        else {
            die $err;
        }
    }
}

class Isilon-Rest-Client does REST::Client {}

my $stash-path;

sub MAIN (
    Str:D   :$isp-server!,                      #= ISP server name (SELECT SERVER_NAME FROM STATUS)
    Str:D   :$isp-admin!,                       #= ISP server Admin account
    Bool    :$nfs,                              #= list NFS shares
    Bool    :$smb,                              #= list SMB shares
    ) {
    get-config();
    my $rest-client;

    my ISP::dsmadmc $dsmadmc   .= new(:$isp-server, :$isp-admin);

    if $nfs {
        my %isp-nodes;
        my %isilon-paths;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%NFS%'"]) -> $node-record {
            %isp-nodes{$node-record<NODE_NAME>} = '?';
        }
        for @nfs-authorities -> $authority {
            $stash-path         = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ $authority ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client        = Isilon-Rest-Client.new(:url('https://' ~ $authority ~ '/platform/1/protocols/nfs/exports'), :$user-id, :insecure, :$stash-path,);
            my $body            = $rest-client.get;
            for $body<exports>.list -> $export {
                for $export<paths>.list -> $path {
                    %isilon-paths{$path} = '?';
                    my $prefix  = '?_';
                    if $path ~~ /^ \/ifs\/j / {
                        $prefix = 'P_';
                    }
                    elsif $path ~~ /^ \/ifs\/c / {
                        $prefix = 'C_';
                    }
                    else {
                        die "?_" ~ $path.IO.basename.uc;
                    }
                    if %isp-nodes{$prefix ~ $path.IO.basename.uc}:exists {
                        %isp-nodes{$prefix ~ $path.IO.basename.uc}  = $path;
                        %isilon-paths{$path}                        = $prefix ~ $path.IO.basename.uc;
                    }
                }
            }
        }
        my @no-rest-presence;
        for %isp-nodes.kv -> $node, $value {
             @no-rest-presence.push: $node if $value eq '?';
        }
        if @no-rest-presence {
            put "The following registered ISP NFS node(s) were not listed in the REST responses:\n";
            .put for @no-rest-presence;
        }
        my @no-node-registered;
        for %isilon-paths.kv -> $path, $value {
             @no-node-registered.push: $path if $value eq '?';
        }
        if @no-node-registered {
            put '' if @no-rest-presence.elems;
            put "The following NFS exports(s) do not have a registered ISP node:\n";
            .put for @no-node-registered;
        }
    }
    elsif $smb {
        my %isp-nodes;
        my %isilon-shares;
        for $dsmadmc.execute(['SELECT', 'NODE_NAME', 'FROM', 'NODES', 'WHERE', 'NODEGROUP', 'LIKE', "'%SMB%'"]) -> $node-record {
            %isp-nodes{$node-record<NODE_NAME>} = '?';
        }
        for @smb-authorities -> $authority {
            $stash-path = $*HOME ~ '/.' ~ $*PROGRAM-NAME.IO.basename ~ '/servers/' ~ $authority ~ '/' ~ $user-id-sterile ~ '.khph';
            $rest-client    = Isilon-Rest-Client.new(:url('https://' ~ $authority ~ '/platform/1/protocols/smb/shares'), :$user-id, :insecure, :$stash-path,);
            my $body        = $rest-client.get;
            for $body<shares>.list -> $share {
                %isilon-shares{$share<name>} = '?';
                my $prefix  = 'SMB_';
                if %isp-nodes{$prefix ~ $share<name>.uc}:exists {
                    %isp-nodes{$prefix ~ $share<name>.uc}   = $share<path>;
                    %isilon-shares{$share<name>.uc}         = $prefix ~ $share<name>.uc;
                }
            }
        }
        my @no-rest-presence;
        for %isp-nodes.kv -> $node, $value {
             @no-rest-presence.push: $node if $value eq '?';
        }
        if @no-rest-presence {
            put "The following registered ISP SMB node(s) were not listed in the REST responses:\n";
            .put for @no-rest-presence;
        }
        my @no-node-registered;
        for %isilon-shares.kv -> $share, $value {
             @no-node-registered.push: $share if $value eq '?';
        }
        if @no-node-registered {
            put '' if @no-rest-presence.elems;
            put "The following SMB share(s) do not have a registered ISP node:\n";
            .put for @no-node-registered;
        }
    }
    else {
        die $*USAGE;
    }
}

=finish

