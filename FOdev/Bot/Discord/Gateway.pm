package FOdev::Bot::Discord::Gateway;

use strict;
use warnings;

use Compress::Zlib;

use Mojo::Base 'Mojo::EventEmitter';
use base       'FOdev::Bot::Base';

# All comments marked with 'protocol' are based on Discord docs
# https://discordapp.com/developers/docs/topics/gateway

my( $dbSession, $dbSeq ) = ( 'session', 'seq' );

my @OPCODE =
(
	'DISPATCH',
	'HEARTBEAT',
	'IDENTIFY',
	'STATUS_UPDATE',
	'VOICE_STATUS_UPDATE',
	'VOICE_SERVER_PING',
	'RESUME',
	'RECONNECT',
	'REQUEST_GUILD_MEMBERS',
	'INVALID_SESSION',
	'HELLO',
	'HEARTBEAT_ACK'
);

my $PERMISSION =
{
	CREATE_INSTANT_INVITE	=> 0x00000001,#* Allows creation of instant invites
	KICK_MEMBERS		=> 0x00000002,#* Allows kicking members
	BAN_MEMBERS		=> 0x00000004,#* Allows banning members
	ADMINISTRATOR		=> 0x00000008,#* Allows all permissions and bypasses channel permission overwrites
	MANAGE_CHANNELS		=> 0x00000010,#* Allows management and editing of channels
	MANAGE_GUILD		=> 0x00000020,#* Allows management and editing of the guild
	ADD_REACTIONS		=> 0x00000040,#  Allows for the addition of reactions to messages
	VIEW_AUDIT_LOG		=> 0x00000080,#  Allows for viewing of audit logs
	READ_MESSAGES		=> 0x00000400,#  Allows reading messages in a channel. The channel will not appear for users without this permission
	SEND_MESSAGES		=> 0x00000800,#  Allows for sending messages in a channel
	SEND_TTS_MESSAGES	=> 0x00001000,#  Allows for sending of /tts messages
	MANAGE_MESSAGES		=> 0x00002000,#* Allows for deletion of other users messages
	EMBED_LINKS		=> 0x00004000,#  Links sent by this user will be auto-embedded
	ATTACH_FILES		=> 0x00008000,#  Allows for uploading images and files
	READ_MESSAGE_HISTORY	=> 0x00010000,#  Allows for reading of message history
	MENTION_EVERYONE	=> 0x00020000,#  Allows for using the @everyone tag to notify all users in a channel, and the @here tag to notify all online users in a channel
	USE_EXTERNAL_EMOJIS	=> 0x00040000,#  Allows the usage of custom emojis from other servers
	CONNECT			=> 0x00100000,#  Allows for joining of a voice channel
	SPEAK			=> 0x00200000,#  Allows for speaking in a voice channel
	MUTE_MEMBERS		=> 0x00400000,#  Allows for muting members in a voice channel
	DEAFEN_MEMBERS		=> 0x00800000,#  Allows for deafening of members in a voice channel
	MOVE_MEMBERS		=> 0x01000000,#  Allows for moving of members between voice channels
	USE_VAD			=> 0x02000000,#  Allows for using voice-activity-detection in a voice channel
	CHANGE_NICKNAME		=> 0x04000000,#  Allows for modification of own nickname
	MANAGE_NICKNAMES	=> 0x08000000,#  Allows for modification of other users nicknames
	MANAGE_ROLES		=> 0x10000000,#* Allows management and editing of roles
	MANAGE_WEBHOOKS		=> 0x20000000,#* Allows management and editing of webhooks
	MANAGE_EMOJIS		=> 0x40000000 #* Allows management and editing of emojis
	# * These permissions require the owner account to use two-factor
	#   authentication when used on a guild that has server-wide 2FA enabled.
};

sub new
{
	my( $class, $bot ) = @_;

	my $self = {
		encoding	=> 'json',

		useragent	=> Mojo::UserAgent->new,
		websocket	=> undef
	};
	bless( $self, $class );

	$self->BOT( $bot );

	return( $self );
}

sub init
{
	my( $self ) = @_;

	$self->UserAgent->name( sprintf( "%s/v%s", $self->BOT->NAME, $self->BOT->VERSION ));
	$self->UserAgent->connect_timeout(0);
	$self->UserAgent->inactivity_timeout(0);

	$self->UserAgent->on( error => sub
	{
		my( $agent, $error ) = @_;

		$self->Log( "ERROR UserAgent\n%s", $error );
	});

	$self->BOT->Discord->on( start => sub{ $self->Start });
	$self->BOT->Discord->on( stop  => sub{ $self->Stop });

	return( $self );
}

##
## get
##

sub Encoding # JIC we'll have ETF support some day
{
	my( $self ) = @_;

	return( $self->{encoding} );
}

sub UserAgent
{
	my( $self ) = @_;

	return( $self->{useragent} );
}

sub WebSocket
{
	my( $self ) = @_;

	return( $self->{websocket} );
}

##
## ()
##

sub Start
{
	my( $self ) = @_;

	$self->Log( "Starting..." );

	$self->Connect( 1 );

	$self->emit( 'start' );

	$self->Log( "Started" );
}

sub Stop
{
	my( $self ) = @_;

	$self->Log( "Stoping..." );

	$self->Disconnect;
	$self->StopHeartbeatLoop; # JIC

	$self->emit( 'stop' );

	$self->Log( "Stopped" );
}

sub Connect
{
	my( $self, $resume ) = @_;

	$resume = 0 if( !defined($resume) );

	delete( $self->{cache} ) if( exists($self->{cache}) );

	# get gateway address via API
	# as side effect, token is validated before opening connection
	my $json = $self->BOT->Discord->API->GET( '/gateway/bot' );

	if( !defined($json) )
	{
		$self->Log( "Cannot GET gateway address. Shut. Down. EVERYTHING." );
		$self->Stop;

		return;
	}

	my $url = $json->{url};
	my $ver = $self->BOT->Discord->API->Version;
	my $enc = $self->Encoding;

	$self->Log( "Connecting to %s [v%d] [%s]%s",
		$url, $ver, $enc,
		$resume ? " [resume]" : '' );

	# encoding parameter is *CRITICAL* - not even OP 10 is sent without it
	# fuck docs for calling it "a good idea" only
	$url .= sprintf( "?v=%d&encoding=%s", $ver, $enc );

	# info for OP 10 handler that we attempt to resume session
	# OP 9 handler must take care of switching to OP 2 if resume fails
	if( $resume && $self->DB->Exists( $dbSession, $dbSeq ))
	{
		$self->{cache}{'hello-resume'} = 1;
	}

	# gateway need to be handled by dedicated useragent
	# it's not possible to use it for GET requests at same time,
	# and we need that for API requests
	$self->UserAgent->websocket( $url => sub
	{
		my( $agent, $websocket ) = @_;

		if( !$websocket->is_websocket )
		{
			$self->Log( 'WebSocket handshake failed!' );
			return;
		}

		# start tracking connection status
		$self->{cache}{connect} = 1;

		$self->{websocket} = $websocket;

		$websocket->on( 'error',      sub{ $self->OnWebSocketError( @_ )});
		$websocket->on( 'connection', sub{ $self->OnWebSocketConnection( @_ )});
		$websocket->on( 'finish',     sub{ $self->OnWebSocketFinish( @_ )});

#		$websocket->on( 'drain', sub{ $self->OnWebSocketDrain( @_ )});
#		$websocket->on( 'frame', sub{ $self->OnWebSocketFrame( @_ )});

		$websocket->on( 'binary',  sub{ $self->OnWebSocketBinary( @_ )});
		$websocket->on( 'text',    sub{ $self->OnWebSocketText( @_ )});
		$websocket->on( 'message', sub{ $self->OnWebSocketMessage( @_ )});
		$websocket->on( 'json',    sub{ $self->OnWebSocketJson( @_ )});
	});
}

sub Disconnect
{
	my( $self, $status ) = @_;

	# stop tracking connection status
	delete( $self->{cache}{connect} );

	if( defined($self->WebSocket) )
	{
		$self->Log( "Disconnecting%s",
			$status ? sprintf( " [status %d]", $status ) : '' );


		# see https://tools.ietf.org/html/rfc6455#section-7.4.1
		#     https://tools.ietf.org/html/rfc6455#section-11.7
		$self->WebSocket->finish( $status || 1000 );
		$self->StopHeartbeatLoop;
	}
}

sub Reconnect
{
	my( $self, $resume ) = @_;

	$resume = 0 if( !defined( $resume ));

	$self->Log( "Reconnecting" );

	$self->Disconnect;
	$self->Connect( $resume );
}

##
## websocket events
##

sub OnWebSocketError
{
	my( $self, $event, $error ) = @_;

	$self->Log( "ERROR WebSocket\n%s", $error );
}

sub OnWebSocketConnection # dead code :(
{
	my( $self, $websocket, $connection ) = @_;

	$self->Log( "CONNECTION" );
}

sub OnWebSocketFinish
{
	my( $self, $websocket, $code, $reason ) = @_;

	$self->Log( "WebSocket closed%s%s",
		$code   ? sprintf( " [code %s]",   $code ) : '',
		$reason ? sprintf( " [reason %s]", $reason ) : '' );

	$self->StopHeartbeatLoop;

	if( defined( $self->{cache}{connect} ))
	{
		$self->Log( "Network error?" );
		Mojo::IOLoop->timer( 5 => sub
		{
			$self->Reconnect( 1 );
		});
	}
}

sub OnWebSocketDrain # debug
{
	my( $self, $websocket ) = @_;

	$self->Log( "DRAIN" );
}

sub OnWebSocketFrame # debug
{
	my( $self, $websocket, $frame ) = @_;

	$self->Log( "FRAME FIN[%s] RSV1[%s] RSV2[%s] RSV3[%s] OPCODE[%s] Payload[%s]",
		$frame->[0], $frame->[1], $frame->[2], $frame->[3], $frame->[4], $frame->[5] );
}

sub OnWebSocketBinary # not used?
{
	my( $self, $websocket, $msg ) = @_;

	$self->Log( "BINARY%s", $msg ? sprintf( " [%s]", $msg ) : '' );
}

sub OnWebSocketText # not used?
{
	my( $self, $websocket, $msg ) = @_;

	$self->Log( "TEXT%s", $msg ? sprintf( " [%s]", $msg ) : '' );
}

sub OnWebSocketMessage
{
	my( $self, $websocket, $msg ) = @_;

	# TODO call uncompress only when using compression...
	my $umsg = uncompress( $msg ); # Compress::Zlib
	if( defined( $umsg ))
	{
		$msg = $umsg;
		$umsg = undef;
	}

	my $json = Mojo::JSON->decode( $msg );

	$msg = sprintf( "RECV OP[%d%s]",
		$json->{op},
		$json->{op} < scalar(@OPCODE)
			? sprintf( ":%s", $OPCODE[$json->{op}] )
			: '' );

	$msg .= sprintf( " SEQ[%d]", $json->{s} ) if( defined($json->{s}) );
	$msg .= sprintf( " NAME[%s]", $json->{t} ) if( defined($json->{t}) );

	# protocol: cache SEQ for SendOp*()
	if( defined($json->{s}) )
	{
		$self->{cache}{seq} = $json->{s};
		$self->DB->Set( $dbSeq, $json->{s} );
	}

	# find OnOp*() and call it
	my $sub = $self->can( sprintf( "OnOp%d", $json->{op} ));
	if( defined($sub) )
	{
		if( $self->Debug )
		{
			$self->Log( $msg );
		}
		else
		{
			$self->LogToFile( $msg );
		}
		$self->DumpToFile( $json->{d}, "OP%d", $json->{op} );

		# protocol: {t} is used by OP 0 only
		\&$sub( $self, $json->{d}, $json->{t} );
	}
	else
	{
		$self->Log( $msg );
		$self->Dump( $json->{d}, "OP%d", $json->{op} );
	}
}

sub OnWebSocketJson # not used?
{
	my( $self, $websocket, $msg ) = @_;

	$self->Log( "JSON %s", $msg ? $msg : '' );
}

##
## gateway events
##

sub OnOp0 # DISPATCH
{
	my( $self, $data, $name ) = @_;

	# EVENT_NAME -> OnEventName
	my @parts = split( /_/, $name );
	$name = 'On';
	foreach my $part( @parts )
	{
		$name .= ucfirst( lc( $part ));
	}

	# find OnEventName() and call it
	my $sub = $self->can( $name );
	if( defined($sub) )
	{
		$self->Log( "EVENT [%s]", $name ) if( $self->Debug );
		\&$sub( $self, $data );
	}
}

sub OnOp1 # HEARTBEAT
{
	my( $self, $data ) = @_;

	$self->Log( "Heart Attack!" ); # "Helena, mam zawał!"
	$self->SendOpHeartbeat;
}

sub OnOp7_ # RECONNECT
{
	my( $self, $data ) = @_;
}

sub OnOp9 # INVALID_SESSION
{
	my( $self, $data ) = @_;

	my $prefix = "Invalid session,";

	if( exists($self->{cache}{'hello-resume'}) )
	{
		# protocol: last session has been invalidated
		#           wait 1-5 seconds before sending OP 2
		delete($self->{cache}{'hello-resume'});

		$self->Log( "%s identifying...", $prefix );

		Mojo::IOLoop->timer( $self->Random(1,5) => sub
		{
			$self->SendOpIdentify;
		});

		return;
	}

	# NOTE not tested, no idea how to trigger such scenario
	# protocol: session can be resumed
	if( $data )
	{
		$self->Log( "%s trying to resume...", $prefix );
		$self->SendOpResume;

		return;
	}

	$self->Log( "%s shutting down...". $prefix );
	$self->Stop; # panic!
}

sub OnOp10 # HELLO
{
	my( $self, $data ) = @_;

	$self->StartHeartbeatLoop( $data->{heartbeat_interval} );

	if( defined( $self->{cache}{'hello-resume'} ))
	{
		$self->SendOpResume;
	}
	else
	{
		$self->SendOpIdentify;
	}
}

sub OnOp11 # HEARTBEAT_ACK
{
	my( $self, $data ) = @_;

	$self->{cache}{heartbeat}{counter}--;
}

sub SendOp
{
	my( $self, $op, $data, $seq, $name ) = @_;

	$self->Log( "SEND OP[%d%s]%s%s",
		$op,
		$op < scalar(@OPCODE) ? sprintf( ":%s", $OPCODE[$op] ) : '',
		defined($seq) ? sprintf( " SEQ[%d]", $seq ) : '',
		defined($name) ? sprintf( " NAME[%d]", $name ) : ''
	) if( $self->Debug );

	my $send =
	{
		op => $op,
		d  => $data
	};

	$send->{s} = $seq   if( defined($seq) );
	$send->{t} = $name if( defined($name) );

	$self->DumpToFile( $send, "OP%d", $op );

	my $json = Mojo::JSON->encode( $send );

	$self->WebSocket->send( $json );
}

sub SendOpHeartbeat # OP 1
{
	my( $self ) = @_;

	$self->{heartbeat}{counter}++;
	$self->{heartbeat}{total}++;
	$self->SendOp( 1, $self->{cache}{seq} || undef );
}

sub SendOpIdentify # OP 2
{
	my( $self ) = @_;

	my $ident =
	{
		# minimal set: token, properties
		#
		# properties CAN be empty, but CANNOT be removed from payload
		# (results in gateway returning OP 9)
		# used only to make Discord devs amazed that someone uses perl

		token      => $self->BOT->Discord->Token,
		compress   => Mojo::JSON->true,
		properties =>
		{
			'$os'      => 'Linux',
			'$device'  => 'Perl',
			'$browser' => 'Mojo'
		}
	};

	$self->SendOp( 2, $ident );
}

sub SendOpResume # OP 6
{
	my( $self ) = @_;

	my $resume =
	{
		# DB entries needs to be verified before calling this function

		token      => $self->BOT->Discord->Token,
		session_id => $self->DB->Get( $dbSession ),
		seq        => $self->DB->Get( $dbSeq )
	};

	$self->SendOp( 6, $resume );
}

sub StartHeartbeatLoop
{
	my( $self, $time_ms ) = @_;

	$self->StopHeartbeatLoop;

	my $time = int($time_ms / 1000);
	$self->Log( "Starting heartbeat loop [%ds]", $time );

	$self->{cache}{heartbeat}{counter} = 0;
	$self->{cache}{heartbeat}{total} = 0;
	$self->{cache}{heartbeat}{loop} = Mojo::IOLoop->recurring( $time, sub
	{
		$self->SendOpHeartbeat;
	});
}

sub StopHeartbeatLoop
{
	my( $self ) = @_;

	if( exists($self->{cache}{heartbeat}) )
	{
		$self->Log( "Stopping heartbeat loop" );

		Mojo::IOLoop->remove( $self->{cache}{heartbeat}{loop} );
		delete( $self->{cache}{heartbeat} );
	}
}

##
## discord events
##

sub OnReady
{
	my( $self, $data ) = @_;

	if( $data->{v} != $self->BOT->Discord->API->Version )
	{
		$self->Log( "WARN gateway version mismatch (gateway:%d vs api:%d)",
			$data->{v}, $self->BOT->API->Version );
	}

	# TEST
	$self->DB->Set( $dbSession, $data->{session_id} );
}

sub OnResumed
{
	my( $self, $data ) = @_;

	$self->Log( "Session resumed" );
}

1;
