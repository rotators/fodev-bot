package FOdev::Bot::Discord;

use strict;
use warnings;

use UNIVERSAL;

use FOdev::Bot::Discord::API;
use FOdev::Bot::Discord::Gateway;

use Mojo::Base 'Mojo::EventEmitter';
use base       'FOdev::Bot::Base';

my( $dbToken ) = ( 'token' );

sub new
{
	my( $class, $bot ) = @_;

	my $self = {
		'api'		=> undef,
		'gateway'	=> undef
	};
	bless( $self, $class );

	$self->BOT( $bot );

	return( $self );
}

sub init
{
	my( $self ) = @_;

	$self->BOT->on( start => sub{ $self->Start; });
	$self->BOT->on( stop  => sub{ $self->Stop; });

	$self->BOT->Commands->on( discord => sub
	{
		my( $commands, @args ) = @_;

		$self->BOT->OnCommand( $self, @args );
	});

	$self->{api}     = FOdev::Bot::Discord::API->new( $self->BOT )->init;
	$self->{gateway} = FOdev::Bot::Discord::Gateway->new( $self->BOT )->init;
}

##
## get
##

sub API
{
	my( $self ) = @_;

	return( $self->{api} );
}

sub Gateway
{
	my( $self ) = @_;

	return( $self->{gateway} );
}

sub Token
{
	my( $self ) = @_;

	return( $self->DB->Get( $dbToken ));
}

##
## methods
##

sub Start
{
	my( $self ) = @_;

	$self->Log( "Starting..." );

	if( !defined($self->Token) )
	{
		$self->Log( "Token not found" );
		return;
	}

	$self->emit( 'start' );

	$self->Log( "Started" );
}

sub Stop
{
	my( $self ) = @_;

	$self->Log( "Stopping..." );
	$self->emit( 'stop' );
	$self->Log( "Stopped" );
}

##
## commands
##

sub CommandApi
{
	my( $self, @args ) = @_;

	if( !scalar(@args) )
	{
		return;
	}

	if( !defined($self->Token) )
	{
		$self->Log( "Token not found" );
		$self->Log( "Use command 'discord token [token]'" );
		return;
	}

	foreach my $path ( @args )
	{
		my $json = $self->API->GET( $path );
		$self->Dump( $json, 'API' );
	}
}

sub CommandToken
{
	my( $self, @args ) = @_;

	if( !scalar(@args) )
	{
		$self->Log( "Token is %sset", !defined($self->Token) ? 'not ' : '' );
		return;
	}

	$self->DB->Set( $dbToken, shift(@args) );
	$self->Log( "Token set" );
}

1;
