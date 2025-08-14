/*
	_bot_chat
	Author: INeedGames
	Date: 05/06/2022
	Does bot chatter.
*/

#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\bots\_bot_utility;

/*
	Init
*/
init()
{
	if ( getdvar( "bots_main_chat" ) == "" )
	{
		setdvar( "bots_main_chat", 1.0 );
	}
    // toggle for action-callout style chat (placing claymore, following, etc.)
    if ( getdvar( "bots_chat_actions" ) == "" )
    {
        setdvar( "bots_chat_actions", 0 );
    }
	
	level thread onBotConnected();
}

/*
	Bot connected
*/
onBotConnected()
{
	for ( ;; )
	{
		level waittill( "bot_connected", bot );
		
		bot thread start_chat_threads();
	}
}

/*
	Does the chatter
*/
BotDoChat( chance, string, isTeam )
{
	mod = getdvarfloat( "bots_main_chat" );
	
	if ( mod <= 0.0 )
	{
		return;
	}
	
	if ( chance >= 100 || mod >= 100.0 || ( randomint( 100 ) < ( chance * mod ) + 0 ) )
	{
		if ( isdefined( isTeam ) && isTeam )
		{
			self sayteam( string );
		}
		else
		{
			self sayall( string );
		}
	}
}

/*
	Threads for bots
*/
start_chat_threads()
{
	self endon( "disconnect" );
	
	self thread start_random_chat();
	self thread start_chat_watch();
	self thread start_killed_watch();
	self thread start_death_watch();
	self thread start_endgame_watch();
	
	self thread start_startgame_watch();
}

/*
	death
*/
start_death_watch()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "death" );
		
		self thread bot_chat_death_watch( self.lastattacker, self.bots_lastks );
		
		self.bots_lastks = 0;
	}
}

/*
	start_endgame_watch
*/
start_endgame_watch()
{
	self endon( "disconnect" );
	
	level waittill ( "game_ended" );
	
	self thread endgame_chat();
}

/*
	Random chatting
*/
start_random_chat()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( randomint( 100 ) < 1 )
		{
			if ( randomint( 100 ) < 1 && isalive( self ) )
			{
				self thread doQuickMessage();
			}
		}
	}
}

/*
	Got a kill
*/
start_killed_watch()
{
	self endon( "disconnect" );
	
	self.bots_lastks = 0;
	
	for ( ;; )
	{
		self waittill( "killed_enemy" );
		wait 0.05;
		
		if ( self.bots_lastks < self.cur_kill_streak )
		{
			for ( i = self.bots_lastks + 1; i <= self.cur_kill_streak; i++ )
			{
				self thread bot_chat_streak( i );
			}
		}
		
		self.bots_lastks = self.cur_kill_streak;
		
		self thread bot_chat_killed_watch( self.lastkilledplayer );
	}
}

/*
	Starts things for the bot
*/
start_chat_watch()
{
	self endon( "disconnect" );
	level endon ( "game_ended" );
	
	for ( ;; )
	{
		self waittill( "bot_event", msg, a, b, c, d, e, f, g );
		
		switch ( msg )
		{
			case "killcam":
				self thread bot_chat_killcam_watch( a, b, c, d, e, f, g );
				break;
				
			case "stuck":
				self thread bot_chat_stuck_watch( a, b, c, d, e, f, g );
				break;
				
            case "tube":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_tube_watch( a, b, c, d, e, f, g ); }
                break;
				
			case "killstreak":
				self thread bot_chat_killstreak_watch( a, b, c, d, e, f, g );
				break;
				
            case "attack_vehicle":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_attack_vehicle_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "follow_threat":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_follow_threat_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "camp":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_camp_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "follow":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_follow_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "equ":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_equ_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "nade":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_nade_watch( a, b, c, d, e, f, g ); }
                break;
				
            case "throwback":
                if ( getdvarint( "bots_chat_actions" ) ) { self thread bot_chat_throwback_watch( a, b, c, d, e, f, g ); }
                break;
				
			case "rage":
				self thread bot_chat_rage_watch( a, b, c, d, e, f, g );
				break;
				
			case "tbag":
				self thread bot_chat_tbag_watch( a, b, c, d, e, f, g );
				break;
				
			case "revenge":
				self thread bot_chat_revenge_watch( a, b, c, d, e, f, g );
				break;
				
			case "heard_target":
				self thread bot_chat_heard_target_watch( a, b, c, d, e, f, g );
				break;
				
			case "uav_target":
				self thread bot_chat_uav_target_watch( a, b, c, d, e, f, g );
				break;
				
			case "attack_equ":
				self thread bot_chat_attack_equ_watch( a, b, c, d, e, f, g );
				break;
				
			case "dom":
				self thread bot_chat_dom_watch( a, b, c, d, e, f, g );
				break;
				
			case "hq":
				self thread bot_chat_hq_watch( a, b, c, d, e, f, g );
				break;
				
			case "sab":
				self thread bot_chat_sab_watch( a, b, c, d, e, f, g );
				break;
				
			case "sd":
				self thread bot_chat_sd_watch( a, b, c, d, e, f, g );
				break;
				
			case "connection":
				self thread bot_chat_connection_player_watch( a, b, c, d, e, f, g );
				break;
				
			case "chat":
				self thread bot_chat_chat_player_watch( a, b, c, d, e, f, g );
				break;
		}
	}
}

/*
	When another player chats
*/
bot_chat_chat_player_watch( chatstr, message, player, is_hidden, e, f, g )
{
	self endon( "disconnect" );
}

/*
	When a player connected
*/
bot_chat_connection_player_watch( conn, player, playername, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( conn )
	{
		case "connected":
			break;
			
		case "disconnected":
			break;
	}
}

/*
	start_startgame_watch
*/
start_startgame_watch()
{
	self endon( "disconnect" );
	
	wait( randomint( 5 ) + randomint( 5 ) );
	
	switch ( level.gametype )
	{
		case "war":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 7, "TEEEEEEEEAM, DEEEEAAAAAATHMAAAAATCH!!" );
					break;
					
				case 1:
					self BotDoChat( 7, "Lets get em guys, wipe the floor with them." );
					break;
					
				case 2:
					self BotDoChat( 7, "Yeeeesss master..." );
					break;
			}
			
			break;
			
		case "dom":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 7, "Yaaayy!! I LOVE DOMINATION!!!!" );
					break;
					
				case 1:
					self BotDoChat( 7, "Lets cap the flags and them." );
					break;
					
				case 2:
					self BotDoChat( 7, "Yeeeesss master..." );
					break;
			}
			
			break;
			
		case "sd":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 7, "Ahhhh! I'm scared! No respawning!" );
					break;
					
				case 1:
					self BotDoChat( 7, "Lets get em guys, wipe the floor with them." );
					break;
					
				case 2:
					self BotDoChat( 7, "Yeeeesss master..." );
					break;
			}
			
			break;
			
		case "sab":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 7, "Soccer/Football! Lets play it!" );
					break;
					
				case 1:
					self BotDoChat( 7, "Who plays sab these days." );
					break;
					
				case 2:
					self BotDoChat( 7, "I do not know what to say." );
					break;
			}
			
			break;
			
		case "dm":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 7, "DEEEEAAAAAATHMAAAAATCH!!" );
					break;
					
				case 1:
					self BotDoChat( 7, "IM GOING TO KILL U ALL" );
					break;
					
				case 2:
					self BotDoChat( 7, "lol sweet. time to camp." );
					break;
			}
			
			break;
			
		case "koth":
			self BotDoChat( 7, "HQ TIME!" );
			break;
	}
}

/*
	Does quick cod4 style message
*/
doQuickMessage()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	if ( !isdefined( self.talking ) || !self.talking )
	{
		self.talking = true;
		soundalias = "";
		saytext = "";
		wait 2;
		self.spamdelay = true;
		
		switch ( randomint( 11 ) )
		{
			case 4 :
				soundalias = "mp_cmd_suppressfire";
				saytext = "Suppressing fire!";
				break;
				
			case 5 :
				soundalias = "mp_cmd_followme";
				saytext = "Follow Me!";
				break;
				
			case 6 :
				soundalias = "mp_stm_enemyspotted";
				saytext = "Enemy spotted!";
				break;
				
			case 7 :
				soundalias = "mp_cmd_fallback";
				saytext = "Fall back!";
				break;
				
			case 8 :
				soundalias = "mp_stm_needreinforcements";
				saytext = "Need reinforcements!";
				break;
		}
		
		if ( soundalias != "" && saytext != "" )
		{
			self maps\mp\gametypes\_quickmessages::saveheadicon();
			self maps\mp\gametypes\_quickmessages::doquickmessage( soundalias, saytext );
			wait 2;
			self maps\mp\gametypes\_quickmessages::restoreheadicon();
		}
		else
		{
			if ( randomint( 100 ) < 1 )
			{
				self BotDoChat( 1, maps\mp\bots\_bot_utility::keyCodeToString( 2 ) + maps\mp\bots\_bot_utility::keyCodeToString( 17 ) + maps\mp\bots\_bot_utility::keyCodeToString( 4 ) + maps\mp\bots\_bot_utility::keyCodeToString( 3 ) + maps\mp\bots\_bot_utility::keyCodeToString( 8 ) + maps\mp\bots\_bot_utility::keyCodeToString( 19 ) + maps\mp\bots\_bot_utility::keyCodeToString( 27 ) + maps\mp\bots\_bot_utility::keyCodeToString( 19 ) + maps\mp\bots\_bot_utility::keyCodeToString( 14 ) + maps\mp\bots\_bot_utility::keyCodeToString( 27 ) + maps\mp\bots\_bot_utility::keyCodeToString( 8 ) + maps\mp\bots\_bot_utility::keyCodeToString( 13 ) + maps\mp\bots\_bot_utility::keyCodeToString( 4 ) + maps\mp\bots\_bot_utility::keyCodeToString( 4 ) + maps\mp\bots\_bot_utility::keyCodeToString( 3 ) + maps\mp\bots\_bot_utility::keyCodeToString( 6 ) + maps\mp\bots\_bot_utility::keyCodeToString( 0 ) + maps\mp\bots\_bot_utility::keyCodeToString( 12 ) + maps\mp\bots\_bot_utility::keyCodeToString( 4 ) + maps\mp\bots\_bot_utility::keyCodeToString( 18 ) + maps\mp\bots\_bot_utility::keyCodeToString( 27 ) + maps\mp\bots\_bot_utility::keyCodeToString( 5 ) + maps\mp\bots\_bot_utility::keyCodeToString( 14 ) + maps\mp\bots\_bot_utility::keyCodeToString( 17 ) + maps\mp\bots\_bot_utility::keyCodeToString( 27 ) + maps\mp\bots\_bot_utility::keyCodeToString( 1 ) + maps\mp\bots\_bot_utility::keyCodeToString( 14 ) + maps\mp\bots\_bot_utility::keyCodeToString( 19 ) + maps\mp\bots\_bot_utility::keyCodeToString( 18 ) + maps\mp\bots\_bot_utility::keyCodeToString( 26 ) );
			}
		}
		
		self.spamdelay = undefined;
		wait randomint( 5 );
		self.talking = false;
	}
}

/*
	endgame_chat
*/
endgame_chat()
{
	self endon( "disconnect" );
	
	wait ( randomint( 6 ) + randomint( 6 ) );
	b = -1;
	w = 999999999;
	winner = undefined;
	loser = undefined;
	
	for ( i = 0; i < level.players.size; i++ )
	{
		player = level.players[ i ];
		
		if ( player.pers[ "score" ] > b )
		{
			winner = player;
			b = player.pers[ "score" ];
		}
		
		if ( player.pers[ "score" ] < w )
		{
			loser = player;
			w = player.pers[ "score" ];
		}
	}
	
	if ( level.teambased )
	{
		winningteam = getWinningTeam();
		
		if ( self.pers[ "team" ] == winningteam )
		{
			switch ( randomint( 21 ) )
			{
				case 0:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Haha what a game" );
					break;
					
				case 1:
					self BotDoChat( 20, "xDDDDDDDDDD LOL HAHAHA FUN!" );
					break;
					
				case 3:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "That was fun" );
					break;
					
				case 4:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Lol my team always wins!" );
					break;
					
				case 5:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Haha if i am on " + winningteam + " my team always wins!" );
					break;
					
				case 2:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gg" );
					break;
					
				case 6:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "GGA, our team was awesome!" );
					break;
					
				case 7:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "My team " + self.pers[ "team" ] + " always wins!!" );
					break;
					
				case 8:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "WOW that was EPIC!" );
					break;
					
				case 9:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Hackers lost haha noobs" );
					break;
					
				case 10:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Nice game!! Good job team!" );
					break;
					
				case 11:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "GGA, Well done team!" );
					break;
					
				case 12:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "LOL! camper noobs lose" );
					break;
					
				case 13:
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "owned." );
					break;
					
				case 14:
					self BotDoChat( 20, "lool we won!!" );
					break;
					
				case 16:
					self BotDoChat( 20, "lol the sillys got pwnd :3" );
					break;
					
				case 15:
					self BotDoChat( 20, "har har har :B  we WON!" );
					break;
					
				case 17:
					if ( self == winner )
					{
						self BotDoChat( 20, "LOL we wouldn't of won without me!" );
					}
					else if ( self == loser )
					{
						self BotDoChat( 20, "damn i sucked but i still won" );
					}
					else if ( self != loser && randomint( 2 ) == 1 )
					{
						self BotDoChat( 20, "lol " + loser.name + " sucked hard!" );
					}
					else if ( self != winner )
					{
						self BotDoChat( 20, "wow " + winner.name + " did very well!" );
					}
					
					break;
					
				case 18:
					if ( self == winner )
					{
						self BotDoChat( 20, "I'm the VERY BEST!" );
					}
					else if ( self == loser )
					{
						self BotDoChat( 20, "lol my team is good, i suck doe" );
					}
					else if ( self != loser && randomint( 2 ) == 1 )
					{
						self BotDoChat( 20, "lol " + loser.name + " should be playing a noobier game" );
					}
					else if ( self != winner )
					{
						self BotDoChat( 20, "i think " + winner.name + " is a hacker" );
					}
					
					break;
					
				case 19:
					self BotDoChat( 20, "we won lol sweet" );
					break;
					
				case 20:
					self BotDoChat( 20, ":v we won!" );
					break;
			}
		}
		else
		{
			if ( winningteam != "none" )
			{
				switch ( randomint( 21 ) )
				{
					case 0:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Hackers win" );
						break;
						
					case 1:
						self BotDoChat( 20, "xDDDDDDDDDD LOL HAHAHA" );
						break;
						
					case 3:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "That wasn't fun" );
						break;
						
					case 4:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Wow my team SUCKS!" );
						break;
						
					case 5:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "My team " + self.pers[ "team" ] + " always loses!!" );
						break;
						
					case 2:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gg" );
						break;
						
					case 6:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "bg" );
						break;
						
					case 7:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "vbg" );
						break;
						
					case 8:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "WOW that was EPIC!" );
						break;
						
					case 9:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Good game" );
						break;
						
					case 10:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Bad game" );
						break;
						
					case 11:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "very bad game" );
						break;
						
					case 12:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "campers win" );
						break;
						
					case 13:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "CAMPER NOOBS!!" );
						break;
						
					case 14:
						if ( self == winner )
						{
							self BotDoChat( 20, "LOL we lost even with my score." );
						}
						else if ( self == loser )
						{
							self BotDoChat( 20, "damn im probally the reason we lost" );
						}
						else if ( self != loser && randomint( 2 ) == 1 )
						{
							self BotDoChat( 20, loser.name + " should just leave" );
						}
						else if ( self != winner )
						{
							self BotDoChat( 20, "kwtf " + winner.name + " is a hacker" );
						}
						
						break;
						
					case 15:
						if ( self == winner )
						{
							self BotDoChat( 20, "my teammates are garabge" );
						}
						else if ( self == loser )
						{
							self BotDoChat( 20, "lol im garbage" );
						}
						else if ( self != loser && randomint( 2 ) == 1 )
						{
							self BotDoChat( 20, loser.name + " sux" );
						}
						else if ( self != winner )
						{
							self BotDoChat( 20, winner.name + " is a noob!" );
						}
						
						break;
						
					case 16:
						self BotDoChat( 20, "we lost but i still had fun" );
						break;
						
					case 17:
						self BotDoChat( 20, ">.> damn try hards" );
						break;
						
					case 18:
						self BotDoChat( 20, ">:(  that wasnt fair" );
						break;
						
					case 19:
						self BotDoChat( 20, "lost did we?" );
						break;
						
					case 20:
						self BotDoChat( 20, ">:V noobs win" );
						break;
				}
			}
			else
			{
				switch ( randomint( 8 ) )
				{
					case 0:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gg" );
						break;
						
					case 1:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "bg" );
						break;
						
					case 2:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "vbg" );
						break;
						
					case 3:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "vgg" );
						break;
						
					case 4:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gg no rm" );
						break;
						
					case 5:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "ggggggggg" );
						break;
						
					case 6:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "good game" );
						break;
						
					case 7:
						self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gee gee" );
						break;
				}
			}
		}
	}
	else
	{
		switch ( randomint( 20 ) )
		{
			case 0:
				if ( self == winner )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Haha Suck it, you all just got pwnd!" );
				}
				else if ( self == loser )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Lol i Sucked in this game, just look at my score!" );
				}
				else if ( self != loser && randomint( 2 ) == 1 )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gga, Bad luck " + loser.name );
				}
				else if ( self != winner )
				{
					self BotDoChat( 20, "This game sucked, " + winner.name + " is such a hacker!!" );
				}
				
				break;
				
			case 1:
				if ( self == winner )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "LOL i just wasted you all!! Whoot whoot!" );
				}
				else if ( self == loser )
				{
					self BotDoChat( 20, "GGA i suck, Nice score " + winner.name );
				}
				else if ( self != loser && randomint( 2 ) == 1 )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Rofl, " + loser.name + " dude, you suck!!" );
				}
				else if ( self != winner )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Nice Score " + winner.name + ", how did you get to be so good?" );
				}
				
				break;
				
			case 2:
				if ( self == winner )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "LOL i just wasted you all!! Whoot whoot!" );
				}
				else if ( self == loser )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "nice wallhacks " + winner.name );
				}
				else if ( self != loser && randomint( 2 ) == 1 )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Lol atleast i did better then " + loser.name );
				}
				else if ( self != winner )
				{
					self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "lolwtf " + winner.name );
				}
				
				break;
				
			case 3:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gee gee" );
				break;
				
			case 4:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "WOW that was EPIC!" );
				break;
				
			case 5:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "Nice Game!" );
				break;
				
			case 6:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "good game" );
				break;
				
			case 7:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gga  c  u  all later" );
				break;
				
			case 8:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "bg" );
				break;
				
			case 9:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "GG" );
				break;
				
			case 10:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gg" );
				break;
				
			case 11:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "vbg" );
				break;
				
			case 12:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "gga" );
				break;
				
			case 13:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "BG" );
				break;
				
			case 14:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "stupid map" );
				break;
				
			case 15:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "ffa sux" );
				break;
				
			case 16:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + ":3 i had fun" );
				break;
				
			case 17:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + ":P nubs are playin" );
				break;
				
			case 18:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "nub nub nub thx 4 the nubs" );
				break;
				
			case 19:
				self BotDoChat( 20, "^" + ( randomint( 6 ) + 1 ) + "damn campers" );
				break;
		}
	}
}

/*
	Got streak
*/
bot_chat_streak( streakCount )
{
	self endon( "disconnect" );
	
	if ( streakCount == 7 )
	{
		if ( isdefined( self.pers[ "hardPointItem" ] ) && self.pers[ "hardPointItem" ] == "helicopter_mp" )
		{
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 33, "Nice! I acheived a chopper!" );
					break;
			}
		}
		else
		{
			self BotDoChat( 33, "Huh?? I dont got my helicopter :((" );
		}
	}
}

/*
	Say killed stuff
*/
bot_chat_killed_watch( victim )
{
	self endon( "disconnect" );
	
	if ( !isdefined( victim ) || !isdefined( victim.name ) )
	{
		return;
	}
	
	message = "";
	
    switch ( randomint( 28 ) )
	{
        case 0: message = ( "ez " + victim.name ); break;
        case 1: message = ( "sit down" ); break;
        case 2: message = ( "ur trash kid" ); break;
        case 3: message = ( "get turned on " + victim.name ); break;
        case 4: message = ( "outgunned" ); break;
        case 5: message = ( "nice try tho" ); break;
        case 6: message = ( "get rekt" ); break;
        case 7: message = ( "holy hitreg lol" ); break;
        case 8: message = ( "lag saved u ngl" ); break;
        case 9: message = ( "im cracked rn" ); break;
        case 10: message = ( "beamed" ); break;
        case 11: message = ( "dont peek me" ); break;
        case 12: message = ( "^" + ( randomint( 6 ) + 1 ) + "ez clap" ); break;
        case 13: message = ( "^" + ( randomint( 6 ) + 1 ) + "get good " + victim.name ); break;
        case 14: message = ( "bro got melted" ); break;
        case 15: message = ( "dont cry " + victim.name ); break;
        case 16: message = ( "aimbot? jk" ); break;
        case 17: message = ( "^" + ( randomint( 6 ) + 1 ) + "ok buddy" ); break;
        case 18: message = ( "sheeeesh" ); break;
        case 19: message = ( "that mp5 hittin" ); break;
        case 20: message = ( "^" + ( randomint( 6 ) + 1 ) + ":)" ); break;
        case 21: message = ( "^" + ( randomint( 6 ) + 1 ) + "ggs" ); break;
        case 22: message = ( "^" + ( randomint( 6 ) + 1 ) + "lol" ); break;
        case 23: message = ( "^" + ( randomint( 6 ) + 1 ) + "nice shots" ); break;
        case 24: message = ( "ez 2v1" ); break;
        case 25: message = ( "ur welcome team" ); break;
        case 26: message = ( "free kill ty" ); break;
        case 27: message = ( "np bro" ); break;
			
		case 14:
			message = ( "^" + ( randomint( 6 ) + 1 ) + "Don't even think that i am hacking cause that was pure skill!" );
			break;
			
		case 15:
			message = ( "LOL xD xDDDD " + victim.name + " sucks! HAHA ROFLMAO" );
			break;
			
		case 16:
			message = ( "Wow that was an easy kill." );
			break;
			
		case 17:
			message = ( "noob down" );
			break;
			
		case 18:
			message = ( "Lol u suck " + victim.name );
			break;
			
		case 19:
			message = ( "PWND!" );
			break;
			
		case 20:
			message = ( "sit down " + victim.name );
			break;
			
		case 21:
			message = ( "wow that was close, but i still got you ;)" );
			break;
			
		case 22:
			message = ( "oooooo! i got u good!" );
			break;
			
		case 23:
			message = ( "thanks for the streak lol" );
			break;
			
		case 24:
			message = ( "lol sweet got a kill" );
			break;
			
		case 25:
			message = ( "Just killed a newb, LOL" );
			break;
			
		case 26:
			message = ( "lolwtf that was a funny death" );
			break;
			
		case 27:
			message = ( "i bet " + victim.name + " is using the arrow keys to move." );
			break;
			
		case 28:
			message = ( "lol its noobs like " + victim.name + " that ruin teams" );
			break;
			
		case 29:
			message = ( "lolwat was that " + victim.name + "?" );
			break;
			
		case 30:
			message = ( "haha thanks " + victim.name + ", im at a " + self.cur_kill_streak + " streak." );
			break;
			
		case 31:
			message = ( "lol " + victim.name + " is at a " + victim.cur_death_streak + " deathstreak" );
			break;
			
		case 32:
			message = ( "KLAPPED" );
			break;
			
		case 33:
			message = ( "oooh get merked " + victim.name );
			break;
			
		case 34:
			message = ( "i love " + getMapName( getdvar( "mapname" ) ) + "!" );
			break;
			
		case 35:
			message = ( getMapName( getdvar( "mapname" ) ) + " is my favorite map!" );
			break;
			
		case 36:
			message = ( "get rekt" );
			break;
			
		case 37:
			message = ( "lol i rekt " + victim.name );
			break;
			
		case 38:
			message = ( "lol ur mum can play better than u!" );
			break;
			
		case 39:
			message = ( victim.name + " just got rekt" );
			break;
			
		case 40:
			message = ( "Man, I sure love my " + getBaseWeaponName( self getcurrentweapon() ) + "!" );
			
			break;
			
		case 41:
			message = ( "lol u got killed " + victim.name + ", kek" );
			break;
	}
	
	wait ( randomint( 3 ) + 1 );
	self BotDoChat( 5, message );
}

/*
	Does death chat
*/
bot_chat_death_watch( killer, last_ks )
{
	self endon( "disconnect" );
	
	if ( !isdefined( killer ) || !isdefined( killer.name ) )
	{
		return;
	}
	
	message = "";
	
    switch ( randomint( 36 ) )
	{
        case 0: message = ( "nah that timing" ); break;
        case 1: message = ( "ok buddy" ); break;
        case 2: message = ( "nice shot ngl" ); break;
        case 3: message = ( "lag spikes wtf" ); break;
			
        case 4:
            if ( last_ks > 0 ) { message = ( "rip streak " + last_ks ); } else { message = ( "spawn killed again..." ); }
            break;
			
        case 5: message = ( "stop spawn killin" ); break;
			
        case 6: message = ( "nice one " + killer.name ); break;
			
        case 7: message = ( "bro ur corning idc" ); break;
			
        case 8: message = ( "n1 " + killer.name ); break;
			
        case 9: message = ( "my ping is chalked" ); break;
			
        case 10: message = ( "ok i got farmed" ); break;
			
        case 11: message = ( "today aint it" ); break;
			
        case 12: message = ( "aaaaa" ); break;
			
        case 13: message = ( "hacker lol" ); break;
			
        case 14: message = ( "wh" ); break;
			
        case 15: message = ( "this game man" ); break;
			
        case 16: message = ( ":o" ); break;
			
        case 17: message = ( "noooo" ); break;
			
        case 18: message = ( "how u hit that" ); break;
			
        case 19: message = ( "lagggg" ); break;
			
        case 20: message = ( "i hate this map" ); break;
			
        case 21: message = ( killer.name + " u a tank fr" ); break;
			
        case 22: message = ( "my isp is done" ); break;
			
        case 23: message = ( "brb" ); break;
			
        case 24: message = ( "random af" ); break;
			
        case 25: message = ( "close one" ); break;
			
        case 26: message = ( "rofl" ); break;
			
        case 27: message = ( "WTF" ); break;
			
        case 28: message = ( "team diff lol" ); break;
			
        case 29: message = ( "stfu kid" ); break;
			
        case 30: message = ( "blocked by teammate nice" ); break;
			
        case 31: message = ( "move team ffs" ); break;
			
        case 32: message = ( "tryhard" ); break;
			
        case 33: message = ( "cope" ); break;
			
        case 34: message = ( "relax bro" ); break;
			
        case 35: message = ( "use a real gun" ); break;
			
		case 36:
			message = ( "k wtf. " + killer.name + " is hacking" );
			break;
			
		case 37:
			message = ( "nice wallhacks " + killer.name );
			break;
			
		case 38:
			message = ( "wh " + killer.name );
			break;
			
		case 39:
			message = ( "cheetos!" );
			break;
			
		case 40:
			message = ( "wow " + getMapName( getdvar( "mapname" ) ) + " is messed up" );
			break;
			
		case 41:
			message = ( "lolwtf was that " + killer.name + "?" );
			break;
			
		case 42:
			message = ( "admin pls ban " + killer.name );
			break;
			
		case 43:
			message = ( "WTF IS WITH THESE SPAWNS??" );
			break;
			
		case 44:
			message = ( "im getting owned lol..." );
			break;
			
		case 45:
			message = ( "someone kill " + killer.name + ", they are on a streak of " + killer.cur_kill_streak + "!" );
			break;
			
		case 46:
			message = ( "man i died" );
			break;
			
		case 47:
			message = ( "nice noob gun " + killer.name );
			break;
			
		case 48:
			message = ( "stop camping " + killer.name + "!" );
			break;
			
		case 49:
			message = ( "k THERE IS NOTHING I CAN DO ABOUT DYING!!" );
			break;
			
		case 50:
			message = ( "aw" );
			break;
			
		case 51:
			message = ( "lol " + getMapName( getdvar( "mapname" ) ) + " sux" );
			break;
			
		case 52:
			message = ( "why are we even playing on " + getMapName( getdvar( "mapname" ) ) + "?" );
			break;
			
		case 53:
			message = ( getMapName( getdvar( "mapname" ) ) + " is such an unfair map!!" );
			break;
			
		case 54:
			message = ( "what were they thinking when making " + getMapName( getdvar( "mapname" ) ) + "?!" );
			break;
			
		case 55:
			message = ( killer.name + " totally just destroyed me!" );
			break;
			
		case 56:
			message = ( "can i be admen plz? so i can ban " + killer.name );
			break;
			
		case 57:
			message = ( "wow " + killer.name + " is such a no life!!" );
			break;
			
		case 58:
			message = ( "man i got rekt by " + killer.name );
			break;
			
		case 59:
			message = ( "admen pls ben " + killer.name );
			break;
			
		case 60:
			message = "Wow! Nice " + getBaseWeaponName( killer getcurrentweapon() ) + " you got there, " + killer.name + "!";
			
			break;
			
		case 61:
			message = ( "you are so banned " + killer.name );
			break;
			
		case 62:
			message = ( "recorded reported and deported! " + killer.name );
			break;
			
		case 63:
			message = ( "hack name " + killer.name + "?" );
			break;
			
		case 64:
			message = ( "dude can you send me that hack " + killer.name + "?" );
			break;
			
		case 65:
			message = ( "nice aimbot " + killer.name + "!!1" );
			break;
			
		case 66:
			message = ( "you are benned " + killer.name + "!!" );
			break;
			
		case 67:
			message = ( "that was topkek " + killer.name );
			break;
	}
	
	wait ( randomint( 3 ) + 1 );
	self BotDoChat( 8, message );
}

/*
	Killcam
*/
bot_chat_killcam_watch( state, b, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 2 ) )
			{
				case 0:
					self BotDoChat( 1, "WTF?!?!?!! Dude youre a hacker and a half!!" );
					break;
					
				case 1:
					self BotDoChat( 1, "Haa! Got my fraps ready, time to watch this killcam." );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 2 ) )
			{
				case 0:
					self BotDoChat( 1, "Wow... Im reporting you!!!" );
					break;
					
				case 1:
					self BotDoChat( 1, "Got it on fraps!" );
					break;
			}
			
			break;
	}
}

/*
	Stuck
*/
bot_chat_stuck_watch( a, b, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	sayLength = randomintrange( 5, 30 );
	msg = "";
	
	for ( i = 0; i < sayLength; i++ )
	{
		switch ( randomint( 9 ) )
		{
			case 0:
				msg = msg + "w";
				break;
				
			case 1:
				msg = msg + "s";
				break;
				
			case 2:
				msg = msg + "d";
				break;
				
			case 3:
				msg = msg + "a";
				break;
				
			case 4:
				msg = msg + " ";
				break;
				
			case 5:
				msg = msg + "W";
				break;
				
			case 6:
				msg = msg + "S";
				break;
				
			case 7:
				msg = msg + "D";
				break;
				
			case 8:
				msg = msg + "A";
				break;
		}
	}
	
	self BotDoChat( 20, msg );
}

/*
	Tube
*/
bot_chat_tube_watch( state, tubeWp, tubeWeap, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "go":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "i am going to go tube" );
					break;
			}
			
			break;
			
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "i tubed" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_killstreak_watch( streakName, b, c, d, e, f, g )
*/
bot_chat_killstreak_watch( state, location, directionYaw, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "call":
			if ( self.pers[ "hardPointItem" ] == "helicopter_mp" )
			{
				self BotDoChat( 20, "wewt! i got the choppa!!" );
			}
			
			break;
	}
}

/*
	bot_chat_attack_vehicle_watch( a, b, c, d, e, f, g )
*/
bot_chat_attack_vehicle_watch( state, vehicle, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 14 ) )
			{
				case 0:
					self BotDoChat( 10, "Not on my watch..." );
					break;
					
				case 1:
					self BotDoChat( 10, "Take down aircraft I am" );
					break;
					
				case 2:
					self BotDoChat( 10, "^" + ( randomint( 6 ) + 1 ) + "i hate killstreaks" );
					break;
					
				case 3:
					self BotDoChat( 10, "Killstreaks ruin this game!!" );
					break;
					
				case 4:
					self BotDoChat( 10, "killstreaks sux" );
					break;
					
				case 5:
					self BotDoChat( 10, "keep the killstreaks comin'" );
					break;
					
				case 6:
					self BotDoChat( 10, "lol see that killstreak? its going to go BOOM!" );
					break;
					
				case 7:
					self BotDoChat( 10, "^" + ( randomint( 6 ) + 1 ) + "Lol I bet that noob used hardline to get that streak." );
					break;
					
				case 8:
					self BotDoChat( 10, "WOW HOW DO YOU GET THAT?? ITS GONE NOW." );
					break;
					
				case 9:
					self BotDoChat( 10, "HAHA say goodbye to your killstreak" );
					break;
					
				case 10:
					self BotDoChat( 10, "All your effort is gone now." );
					break;
					
				case 11:
					self BotDoChat( 10, "I hope there are flares on that killstreak." );
					break;
					
				case 12:
					self BotDoChat( 10, "lol u silly, i'm taking down killstreaks :3 xDD" );
					break;
					
				case 13:
					weap = "rpg_mp";
					
					if ( !self getammocount( "weap" ) )
					{
						weap = self getcurrentweapon();
					}
					
					self BotDoChat( 10, "Im going to takedown your ks with my " + getBaseWeaponName( weap ) );
					break;
			}
			
			break;
			
		case "stop":
			break;
	}
}

/*
	bot_chat_follow_threat_watch( a, b, c, d, e, f, g )
*/
bot_chat_follow_threat_watch( state, threat, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			break;
			
		case "stop":
			break;
	}
}

/*
	bot_chat_camp_watch( a, b, c, d, e, f, g )
*/
bot_chat_camp_watch( state, wp, time, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "go":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 10, "going to camp for " + time + " seconds" );
					break;
					
				case 1:
					self BotDoChat( 10, "time to go camp!" );
					break;
					
				case 2:
					self BotDoChat( 10, "rofl im going to camp" );
					break;
			}
			
			break;
			
		case "start":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 10, "well im camping... this is fun!" );
					break;
					
				case 1:
					self BotDoChat( 10, "lol im camping, hope i kill someone" );
					break;
					
				case 2:
					self BotDoChat( 10, "im camping! i guess ill wait " + time + " before moving again" );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 10, "finished camping.." );
					break;
					
				case 1:
					self BotDoChat( 10, "wow that was a load of camping!" );
					break;
					
				case 2:
					self BotDoChat( 10, "well its been over " + time + " seconds, i guess ill stop camping" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_follow_watch( a, b, c, d, e, f, g )
*/
bot_chat_follow_watch( state, player, time, d, e, f, g )
{
	self endon( "disconnect" );
	
	if ( !isdefined( player ) )
	{
		return;
	}
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 3 ) )
			{
				case 0:
					self BotDoChat( 10, "well im going to follow " + player.name + " for " + time + " seconds" );
					break;
					
				case 1:
					self BotDoChat( 10, "Lets go together " + player.name + " <3 :)" );
					break;
					
				case 2:
					self BotDoChat( 10, "lets be butt buddies " + player.name + " and ill follow you!" );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 2 ) )
			{
				case 0:
					self BotDoChat( 10, "well that was fun following " + player.name + " for " + time + " seconds" );
					break;
					
				case 1:
					self BotDoChat( 10, "im done following that guy" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_equ_watch
*/
bot_chat_equ_watch( state, wp, weap, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "go":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "going to place a " + getBaseWeaponName( weap ) );
					break;
			}
			
			break;
			
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "placed a " + getBaseWeaponName( weap ) );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_nade_watch
*/
bot_chat_nade_watch( state, wp, weap, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "go":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "going to throw a " + getBaseWeaponName( weap ) );
					break;
			}
			
			break;
			
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "threw a " + getBaseWeaponName( weap ) );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_throwback_watch
*/
bot_chat_throwback_watch( state, nade, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "i am going to throw back the grenade!" );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "i threw back the grenade!" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_tbag_watch
*/
bot_chat_tbag_watch( state, who, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "go":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 50, "Im going to go tBag XD" );
					break;
			}
			
			break;
			
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 50, "Im going to tBag XD" );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 50, "Awwww yea... How do you like that? XD" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_rage_watch
*/
bot_chat_rage_watch( state, b, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 5 ) )
			{
				case 0:
					self BotDoChat( 80, "K this is not going as I planned." );
					break;
					
				case 1:
					self BotDoChat( 80, "Screw this! I'm out." );
					break;
					
				case 2:
					self BotDoChat( 80, "Have fun being owned." );
					break;
					
				case 3:
					self BotDoChat( 80, "MY TEAM IS GARBAGE!" );
					break;
					
				case 4:
					self BotDoChat( 80, "kthxbai hackers" );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_revenge_watch
*/
bot_chat_revenge_watch( state, loc, killer, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "Im going to check out my death location." );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 10, "i checked out my deathlocation..." );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_heard_target_watch
*/
bot_chat_heard_target_watch( state, heard, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 5, "I think I hear " + heard.name + "..." );
					break;
			}
			
			break;
			
		case "stop":
			switch ( randomint( 1 ) )
			{
				case 0:
					self BotDoChat( 5, "Well i checked out " + heard.name + "'s location..." );
					break;
			}
			
			break;
	}
}

/*
	bot_chat_uav_target_watch
*/
bot_chat_uav_target_watch( state, heard, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			break;
			
		case "stop":
			break;
	}
}

/*
	bot_chat_attack_equ_watch
*/
bot_chat_attack_equ_watch( state, equ, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( state )
	{
		case "start":
			break;
			
		case "stop":
			break;
	}
}

/*
	bot_chat_dom_watch
*/
bot_chat_dom_watch( state, sub_state, flag, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( sub_state )
	{
		case "spawnkill":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defend":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "cap":
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
	}
}

/*
	bot_chat_hq_watch
*/
bot_chat_hq_watch( state, sub_state, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( sub_state )
	{
		case "cap":
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defend":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
	}
}

/*
	bot_chat_sab_watch
*/
bot_chat_sab_watch( state, sub_state, c, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( sub_state )
	{
		case "bomb":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defuser":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "planter":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "plant":
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defuse":
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
	}
}

/*
	bot_chat_sd_watch
*/
bot_chat_sd_watch( state, sub_state, obj, d, e, f, g )
{
	self endon( "disconnect" );
	
	switch ( sub_state )
	{
		case "bomb":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defuser":
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "planter":
			site = obj;
			
			switch ( state )
			{
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "plant":
			site = obj;
			
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
			
		case "defuse":
			switch ( state )
			{
				case "go":
					break;
					
				case "start":
					break;
					
				case "stop":
					break;
			}
			
			break;
	}
}
