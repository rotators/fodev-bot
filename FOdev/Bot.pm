package FOdev::Bot;

use strict;
use warnings;

use Data::Dumper;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::UserAgent;

use FOdev::Bot::Base; # just to make 'use base' happy
use FOdev::Bot::Commands;
use FOdev::Bot::DB;
use FOdev::Bot::Discord;

use Mojo::Base 'Mojo::EventEmitter';

my( $NAME, $VERSION ) = ( 'FOdev::Bot', '0.01' );

sub new
{
	my( $class ) = @_;

	my $self = {
		daemon		=> 0,
		debug		=> 0,

		commands	=> undef,
		discord		=> undef,
		useragent	=> Mojo::UserAgent->new
	};

	bless( $self, $class );

	$self->{commands} = FOdev::Bot::Commands->new( $self );
	$self->{discord}  = FOdev::Bot::Discord->new( $self );

	$self->UserAgent->name( sprintf( "%s/v%s", $self->NAME, $self->VERSION ));
	$self->UserAgent->connect_timeout(0);
	$self->UserAgent->inactivity_timeout(0);


	$self->UserAgent->on( error => sub
	{
		my( $agent, $error ) = @_;

		$self->Log( "ERROR UserAgent\n%s", $error );
	});

	$self->Commands->init;
	$self->Discord->init;

	return( $self );
}

##
## get
##

sub NAME
{
	my( $self ) = @_;

	return( $NAME );
}

sub VERSION
{
	my( $self ) = @_;

	return( $VERSION );
}

sub Commands
{
	my( $self ) = @_;

	return( $self->{commands} );
}

sub Discord
{
	my( $self ) = @_;

	return( $self->{discord} );
}

sub UserAgent
{
	my( $self ) = @_;

	return( $self->{useragent} );
}

##
## get+set
##

sub Daemon # TODO, not implemented
{
	my $self = shift;
	$self->{daemon} = shift if( scalar(@_) == 1 );
	return( $self->{daemon} );
}

sub Debug
{
	my $self = shift;
	$self->{debug} = shift if( scalar(@_) == 1 );
	return( $self->{debug} );
}

sub LogName
{
	my $self = shift;
	$self->{logname} = shift if( scalar(@_) == 1 );
	return( $self->{logname} );
}

##
## ()
##

sub Log
{
	my( $self, $format, @args ) = @_;

	$format = sprintf( $format, @args ) if( scalar(@args) );

	print( STDOUT $format . "\n" );

	$self->LogToFile( $format );
}

sub LogToFile
{
	my( $self, $format, @args ) = @_;

	if( defined($self->LogName) &&
	    (-w $self->LogName || !-e $self->LogName) &&
	    open( my $file, '>>', $self->LogName ))
	{
		$format = sprintf( $format, @args ) if( scalar(@args) );

		my @time = localtime(time);

		printf( $file "[%02d.%02d.%02d %02d:%02d:%02d] %s\n",
			$time[3], $time[4]+1, ($time[5] += 1900) % 100,
			$time[2], $time[1], $time[0],
			$format );

		close( $file );
	}
}

sub Dump
{
	my( $self, $what, $format, @args ) = @_;

	$format = sprintf( $format, @args ) if( scalar( @args ));

	my $dump = Data::Dumper->new( [$what], [$format] );
	$self->Log( $dump->Indent(1)->Deepcopy(1)->Dump );
}

sub DumpToFile
{
	my( $self, $what, $format, @args ) = @_;

	$format = sprintf( $format, @args ) if( scalar( @args ));

	my $dump = Data::Dumper->new( [$what], [$format] );
	$self->LogToFile( $dump->Indent(1)->Deepcopy(1)->Dump );
}

##
## HTTP GET request
##
sub GET
{
	my( $self, $content_type, $url, @args ) = @_;
	$url = sprintf( $url, @args ) if( scalar(@args) );

	$content_type = lc($content_type);

	$self->Log( "GET [%s]", $url ) if( $self->Debug );

	my $response = $self->UserAgent->get( $url )->res;

	if( $response->code != 200 )
	{
		$self->Log( "%s : %s : %s", $url, $response->code, $response->message );
		return( undef );
	}
	elsif( $content_type ne lc($response->headers->content_type) )
	{
		$self->Log( "%s : expected %s, got %s",
			$url, $content_type, lc($response->headers->content_type) );
		$self->Log( $response->body )
			if( $self->Debug );
		return( undef );
	}
	if( $content_type eq 'application/json' )
	{
		my $json; eval{ $json = Mojo::JSON->decode( $response->body ); };
		if( $@ )
		{
			my $message = $@;
			$self->Log( "%s : JSON error : %s", $url, $message || '?!?' );
			return( undef );
		}
		$response = $json;
	}
=for LWP legacy
	elsif( $content_type eq 'text/html' )
	{
		$response = $response->content;
	}
	elsif( $content_type eq 'text/xml' )
	{
		my $xml = eval{ XMLin( $response->content ); };
		if( $@ )
		{
			my $message = $@;
			$self->Log( "%s : XML error : %s", $url, $message );
			return( 0 );
		}

		$response = $xml;
	}
=cut
	else
	{
		$self->Log( "%s : Unhandled content type : %s",
			$url, $content_type );
		return( undef );
	}
	return( $response );
}

sub Start # any changes here requires restart (when using Module::Refresh)
{
	my( $self ) = @_;

	$self->Log( "%s v%s starting...", $self->NAME, $self->VERSION );

	$SIG{INT} = $SIG{QUIT} = sub
	{
		print( STDOUT "\r" . (' ' x 70) . "\r" );
		$self->Stop;
	};

	if( defined($self->LogName) && -e $self->LogName )
	{
		unlink( $self->LogName );
	}

	$self->Commands->Start;

	$self->emit( 'start' );

	$self->Log( "%s started", $self->NAME );

	Mojo::IOLoop->start;
}

sub Stop 
{
	my( $self ) = @_;

	$self->Commands->Stop;

	$self->Log( "%s stopping...", $self->NAME );

	$self->emit( 'stop' );

	$self->Log( "%s stopped", $self->NAME );

	Mojo::IOLoop->stop;
}

sub Run # any changes here requires restart (when using Module::Refresh)
{
	my( $self ) = @_;

	$self->Commands->on( bot => sub
	{
		my( $commands, @args ) = @_;

		$self->OnCommand( $self, @args );
	});

	$self->Start;
}

sub OnCommand
{
	my( $self, $target, @args ) = @_;

	if( !scalar(@args) )
	{
		return;
	}

	my $cmd = ucfirst( lc( shift( @args )));
	my $msg = sprintf( "COMMAND [%s]%s",
		$cmd,
		scalar(@args) ? sprintf( " [%s]", join( ' ', @args )) : ''
	);
	my $sub = $target->can( sprintf( "Command%s", $cmd ));
	if( defined($sub) )
	{
		$target->Log( $msg ) if( $self->Debug );
		\&$sub( $target, @args );
	}
	else
	{
		$target->Log( "UNKNOWN %s", $msg );
	}
}

sub CommandDump
{
	my( $self ) = @_;

	$self->Dump( $self, 'BOT' );
}

sub CommandStop
{
	my( $self, @args ) = @_;

	$self->Stop;
}

1;
