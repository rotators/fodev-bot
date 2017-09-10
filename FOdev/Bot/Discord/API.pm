package FOdev::Bot::Discord::API;

use strict;
use warnings;

use base 'FOdev::Bot::Base';

sub new
{
	my( $class, $bot ) = @_;

	my $self =
	{
		url	=> 'https://discordapp.com/api',
		version	=> 6,
	};
	bless( $self, $class );

	$self->BOT( $bot );

	return( $self );
}

##
## get
##

sub URL
{
	my( $self ) = @_;

	my $url = $self->{url};
	$url .= sprintf( "/v%d", $self->Version );

	return( $url );
}

sub Version
{
	my( $self ) = @_;

	return( $self->{version} );
}

##
## ()
##

##
## API GET request
##
sub GET
{
	my( $self, $path ) = @_;

	return( undef ) if( !defined($path) );
	if( !($path =~ /^\//) )
	{
		$self->Log( "Path must start with '/'" );
		return( undef );
	}

	$self->Log( "GET %s", $path ) if( $self->Debug );
	$self->BOT->UserAgent->once( start => sub
	{
		my( $agent, $client ) = @_;

		$client->req->headers->header('Authorization', sprintf( "Bot %s", $self->BOT->Discord->Token ));
	});

	my $json = $self->BOT->GET( 'application/json', "%s%s", $self->URL, $path );

	return( $json );
}

1;
