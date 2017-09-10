package FOdev::Bot::Commands;

use strict;
use warnings;

use Mojo::IOLoop::Stream;

use Mojo::Base 'Mojo::EventEmitter';
use base       'FOdev::Bot::Base';

sub new
{
	my( $class, $bot ) = @_;

	my $self =
	{
		'read' => Mojo::IOLoop::Stream->new( \*STDIN )->timeout( 0 )
	};
	bless( $self, $class );

	$self->BOT( $bot );

	return( $self );
}

sub set
{
	my( $self ) = @_;

	$self->{read}->on( read => sub
	{
		my( $stream, $bytes ) = @_;

		$self->{read}->stop;

		chomp( $bytes );
		$bytes =~ s!^[\ \t]+!!;
		$bytes =~ s![\ \t]+$!!;
		my @args = split( /[\ \t]+/, $bytes );
		my $cmd = shift( @args );
		$self->emit( $cmd => @args );

		$self->{read}->start;
	});

	return( $self );
}

sub Start
{
	my( $self ) = @_;

	$self->{read}->start;
}

sub Stop
{
	my( $self ) = @_;

	$self->{read}->stop;
}

1;
