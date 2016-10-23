package Bread::Runner;
use 5.020;
use strict;
use warnings;

# ABSTRACT: run ALL the apps via Bread::Board

our $VERSION = '0.900';

use Carp;
use Module::Runtime qw(use_module);
use Scalar::Util qw(blessed);
use Getopt::Long;
use Log::Any qw($log);
use Try::Tiny;

=method setup

=cut

sub setup {
    my ( $class, $bb_class, $opts ) = @_;
    $opts ||= {};

    my $service_name = $opts->{service} || $0;
    $service_name =~ s{^(?:.*\bbin/)(.+)$}{$1};
    $service_name =~ s{/}{_}g;

    my $bb = $class->compose_breadboard( $bb_class, $opts );

    my $bb_container = $opts->{container} || 'App';
    my $service_bb = try {
        $bb->fetch( $bb_container . '/' . $service_name );
    }
    catch {
        $log->error($_);
        croak $_;
    };

    my $service_class = $service_bb->class;
    use_module($service_class);

    my $service;
    if ( $service_bb->has_parameters ) {
        my $params = $service_bb->parameters;
        my @spec;
        while ( my ( $name, $def ) = each %$params ) {
            my $spec = "$name";
            if ( my $isa = $def->{isa} ) {
                if    ( $isa eq 'Int' )      { $spec .= "=i" }
                elsif ( $isa eq 'Str' )      { $spec .= "=s" }
                elsif ( $isa eq 'Bool' )     { $spec .= '!' }
                elsif ( $isa eq 'ArrayRef' ) { $spec .= '=s@' }
            }

            # TODO required
            # TODO default
            # TODO maybe we can use MooseX::Getopt?
            push( @spec, $spec );
        }
        my %commandline;

        GetOptions( \%commandline, @spec );
        $service = $service_bb->get( \%commandline );
    }
    else {
        $service = $service_bb->get;
    }

    return ($bb, $service);
}

=method compose_breadboard

=cut

sub compose_breadboard {
    my ( $class, $bb_class, $opts ) = @_;

    use_module($bb_class);
    my $init_method = $opts->{init_method} || 'init';
    if ( $bb_class->can($init_method) ) {
        return $bb_class->$init_method($opts);
    }
    else {
        my $msg =
            "$bb_class does not implement a method $init_method (to compose the Bread::Board)";
        $log->error($msg);
        croak $msg;
    }
}

=method run

=cut

sub run {
    my ( $class, $bb_class, $opts ) = @_;

    my ($bb, $service) = $class->setup($bb_class, $opts);

    $class->_hook( 'pre_run', $bb, $service, $opts ) if $opts->{pre_run};

    my $run_methods = $opts->{run_method} || ['run'];
    $run_methods = [$run_methods] unless ref($run_methods) eq 'ARRAY';
    my $method;
    foreach my $m (@$run_methods) {
        next unless $service->can($m);
        $method = $m;
        last;
    }
    unless ($method) {
        my $msg = ref($service)." does not provide any run_method: "
            . join( ', ', @$run_methods );
        $log->error($msg);
        croak $msg;
    }

    my $rv = try {
        return $service->$method;
    }
    catch {
        my $e = $_;
        my $msg;
        if ( blessed($e) && $e->can('message') ) {
            $msg = $e->message;
        }
        else {
            $msg = $e;
        }
        $log->errorf( "%s died with %s", $method, $msg );
        croak $msg;
    };

    $class->_hook( 'post_run', $bb, $service, $opts ) if $opts->{post_run};
    return $rv;
}

sub _hook {
    my ( $class, $hook_name, $bb, $service, $opts ) = @_;

    my $hook = $opts->{$hook_name};
    try {
        $log->infof( "Running hook %s", $hook_name );
        $hook->( $service, $bb, $opts );
    }
    catch {
        $log->errorf( "Could not run hook %s: %s", $hook_name, $_ );
        croak $_;
    }
}

1;

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 OPTIONS

=head3 service

=head3 container

=head3 init_method

=head3 run_method

=head3 pre_run

=head3 post_run

=head2 HOOKS

