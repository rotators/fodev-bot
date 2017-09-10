package FOdev::Bot::DB;

use strict;
use warnings;

use Mojo::JSON;

sub new
{
	my( $class, $file ) = @_;

	die( "Database file not defined\n" ) if( !defined($file) );

	my $self =
	{
		db	=> $file
	};
	bless( $self, $class );

	#

	return( $self );
}

sub Load
{
	my( $self ) = @_;

	my $db = undef;

	if( -r $self->{db} && open( my $dbfile, '<', $self->{db} ))
	{
		local $/;
		my $dbtext = <$dbfile>;
		close( $dbfile );

		eval{ $db = Mojo::JSON->decode( $dbtext )};
	}
	else
	{
		$db = {};
	}

	return( $db );
}

sub Save
{
	my( $self, $db ) = @_;

	my $dbtext = Mojo::JSON->encode( $db );
	if( open( my $dbfile, '>', $self->{db} ))
	{
		printf( $dbfile $dbtext );
		close( $dbfile );
	}
	else
	{
		printf( STDERR "Cannot save DB [%s]\n", $self->{db} );
	}
}

sub Get
{
	my( $self, $var ) = @_;

	return( undef ) if( !defined($var) );

	my $db = $self->Load;

	if( exists($db->{$var}) )
	{
		return( $db->{$var} );
	}

	return( undef );
}

sub Set
{
	my( $self, $var, $val ) = @_;

	return if( !defined($var) );

	my $db = $self->Load;

	$db->{$var} = $val;

	$self->Save( $db );
}

sub Exists
{
	my( $self, @vars ) = @_;

	return( 0 ) if( !scalar(@vars) );

	my $db = $self->Load;

	foreach my $var ( @vars )
	{
		return( 0 ) if( !exists($db->{$var}) );
	}

	return( 1 );
}

1;
