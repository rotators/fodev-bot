package FOdev::Bot::Base;

use strict;
use warnings;

use Cwd 'abs_path';
use File::Basename;
use Math::Random::MT; # TODO use Math::Random::MT::Auto

use FOdev::Bot::DB;

my $MT = Math::Random::MT->new;

##
## get
##

sub DB
{
	my( $self ) = @_;

	my( $name ) = ref( $self )=~ m!FOdev::Bot::(.+)!;
	$name =~ s!::!\.!g;

	my $db = sprintf( "%s/DB/%s.json", dirname( abs_path( $0 )), $name );

	# TODO? autocreate directory

	return( FOdev::Bot::DB->new( $db ));
}

##
## get+set
##

sub BOT
{
	my $self = shift;
	$self->{BOT} = shift if( scalar(@_) == 1 );
	return( $self->{BOT} );
}

sub Debug
{
	my $self = shift;
	$self->{debug} = shift if( scalar(@_) == 1 );
	return( $self->{debug} || $self->BOT->Debug );
}

##
## ()
##

sub Log
{
	my( $self, $format, @args ) = @_;

	my( $name ) = ref( $self )=~ m!FOdev::Bot::(.+)!;

	return( $self->BOT->Log( "[$name] " . $format, @args ));
}

sub LogToFile
{
	my( $self, $format, @args ) = @_;

	my( $name ) = ref( $self )=~ m!FOdev::Bot::(.+)!;

	return( $self->BOT->LogToFile( "[$name] " . $format, @args ));
}

sub Dump
{
	my( $self, @args ) = @_;

	return( $self->BOT->Dump( @args ));
}

sub DumpToFile
{
	my( $self, @args ) = @_;

	return( $self->BOT->DumpToFile( @args ));
}

sub Random
{
	my( $self, $min, $max ) = @_;

	return( int( $MT->rand( $max - $min + 1 )) + $min );
}

1;
