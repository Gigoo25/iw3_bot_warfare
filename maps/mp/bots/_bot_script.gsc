#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\bots\_bot_utility;

/*
	When the bot gets added into the game.
*/
added()
{
	self endon( "disconnect" );
	
	rankxp = self bot_get_rank();
	self setstat( int( tablelookup( "mp/playerStatsTable.csv", 1, "rankxp", 0 ) ), rankxp );
	
	self setstat( int( tablelookup( "mp/playerStatsTable.csv", 1, "plevel", 0 ) ), self bot_get_prestige() );
	
	self set_diff();
	self bot_apply_carry();
	
	self set_class( rankxp );
}

/*
	When the bot connects to the game.
*/
connected()
{
	self endon( "disconnect" );
	
	self.killerlocation = undefined;
	self.lastkiller = undefined;
	self.bot_change_class = true;
	
	self thread difficulty();
	self thread teamWatch();
	self thread classWatch();
	self thread onBotSpawned();
	self thread onSpawned();
	self thread onDeath();
	self thread onKillcam();
	self thread bot_lifecycle();
	
	wait 0.1;
	self.challengedata = [];
}

/*
	watches when the bot enters a killcam
*/
onKillcam()
{
	level endon( "game_ended" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "begin_killcam" );
		
		self thread doKillcamStuff();
	}
}

/*
	bots use copy cat and skip killcams
*/
doKillcamStuff()
{
	self endon( "disconnect" );
	self endon( "spawned_player" );
	
	self BotNotifyBotEvent( "killcam", "start" );
	
	wait 0.5 + randomint( 3 );
	
	wait 0.1;
	
	self thread BotPressUse( 0.6 );
	
	self BotNotifyBotEvent( "killcam", "stop" );
}

/*
	The callback for when the bot gets killed.
*/
onKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration )
{
	self.killerlocation = undefined;
	self.lastkiller = undefined;
	
	if ( !isdefined( self ) || !isdefined( self.team ) )
	{
		return;
	}
	
	if ( sMeansOfDeath == "MOD_FALLING" || sMeansOfDeath == "MOD_SUICIDE" )
	{
		return;
	}
	
	if ( iDamage <= 0 )
	{
		return;
	}
	
	if ( !isdefined( eAttacker ) || !isdefined( eAttacker.team ) )
	{
		return;
	}
	
	if ( eAttacker == self )
	{
		return;
	}
	
	if ( level.teambased && eAttacker.team == self.team )
	{
		return;
	}
	
	bot_record_fight( self.origin );
	
	if ( !isdefined( eInflictor ) || eInflictor.classname != "player" )
	{
		return;
	}
	
	if ( !isalive( eAttacker ) )
	{
		return;
	}
	
	bot_record_fight( eAttacker.origin );
	self.killerlocation = eAttacker.origin;
	self.lastkiller = eAttacker;
}

/*
	The callback for when the bot gets damaged.
*/
onDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset )
{
	if ( !isdefined( self ) || !isdefined( self.team ) )
	{
		return;
	}
	
	if ( !isalive( self ) )
	{
		return;
	}
	
	if ( sMeansOfDeath == "MOD_FALLING" || sMeansOfDeath == "MOD_SUICIDE" )
	{
		return;
	}
	
	if ( iDamage <= 0 )
	{
		return;
	}
	
	if ( !isdefined( eAttacker ) || !isdefined( eAttacker.team ) )
	{
		return;
	}
	
	if ( eAttacker == self )
	{
		return;
	}
	
	if ( level.teambased && eAttacker.team == self.team )
	{
		return;
	}
	
	if ( !isdefined( eInflictor ) || eInflictor.classname != "player" )
	{
		return;
	}
	
	if ( !isalive( eAttacker ) )
	{
		return;
	}
	
	if ( !issubstr( sWeapon, "_silencer_" ) )
	{
		self bot_cry_for_help( eAttacker );
	}
	
	// Humans shot from an unseen angle need startle + turn time; they do
	// not instantly know the exact shooter. Delay the forced acquisition.
	self thread delayedSetAttacker( eAttacker, randomintrange( 300, 700 ) );
}

/*
	Grants attacker knowledge after a human-like delay. Dropping the exact
	instant awareness bots had (a wallhack tell).
*/
delayedSetAttacker( attacker, delayMs )
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	wait delayMs / 1000;
	
	if ( !isdefined( attacker ) || !isalive( attacker ) || !isalive( self ) )
	{
		return;
	}
	
	if ( level.teambased && isdefined( attacker.team ) && isdefined( self.team ) && attacker.team == self.team )
	{
		return;
	}
	
	self SetAttacker( attacker );
}

/*
	When the bot gets attacked, have the bot ask for help from teammates.
*/
bot_cry_for_help( attacker )
{
	if ( !level.teambased )
	{
		return;
	}
	
	theTime = gettime();
	
	if ( isdefined( self.help_time ) && theTime - self.help_time < 1000 )
	{
		return;
	}
	
	self.help_time = theTime;
	
	for ( i = level.players.size - 1; i >= 0; i-- )
	{
		player = level.players[ i ];
		
		if ( !player is_bot() )
		{
			continue;
		}
		
		if ( !isdefined( player.team ) )
		{
			continue;
		}
		
		if ( !player IsPlayerModelOK() )
		{
			continue;
		}
		
		if ( !isalive( player ) )
		{
			continue;
		}
		
		if ( player == self )
		{
			continue;
		}
		
		if ( player.team != self.team )
		{
			continue;
		}
		
		dist = player.pers[ "bots" ][ "skill" ][ "help_dist" ];
		dist *= dist;
		
		if ( distancesquared( self.origin, player.origin ) > dist )
		{
			continue;
		}
		
		if ( randomint( 100 ) < 50 )
		{
			player thread delayedSetAttacker( attacker, randomintrange( 500, 1000 ) );
			
			if ( randomint( 100 ) > 70 )
			{
				break;
			}
		}
	}
}

/*
	Allows the bot to spawn when force respawn is disabled
	Watches when the bot dies
*/
onDeath()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "death" );
		
		self.wantsafespawn = true;
	}
}

/*
	Chooses a random class
*/
chooseRandomClass()
{
	class = "";
	rank = self maps\mp\gametypes\_rank::getrankforxp( self getstat( int( tablelookup( "mp/playerStatsTable.csv", 1, "rankxp", 0 ) ) ) ) + 1;
	
	if ( rank < 4 || randomint( 100 ) < 2 )
	{
		while ( class == "" )
		{
			switch ( randomint( 5 ) )
			{
				case 0:
					class = "assault_mp";
					break;
					
				case 1:
					class = "specops_mp";
					break;
					
				case 2:
					class = "heavygunner_mp";
					break;
					
				case 3:
					if ( rank >= 2 )
					{
						class = "demolitions_mp";
					}
					
					break;
					
				case 4:
					if ( rank >= 3 )
					{
						class = "sniper_mp";
					}
					
					break;
			}
		}
	}
	else
	{
		// Players main one class and occasionally swap; not uniform over 5.
		class = "custom" + bot_weighted_pick( "1:65,2:20,3:7,4:5,5:3", undefined );
	}
	
	return class;
}

/*
	Selects a class for the bot.
*/
classWatch()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		while ( !isdefined( self.pers[ "team" ] ) || !allowClassChoice() )
		{
			wait .05;
		}
		
		wait 0.5;
		
		if ( !maps\mp\gametypes\_globallogic::isvalidclass( self.class ) || !isdefined( self.bot_change_class ) )
		{
			// mod warfare shtuff
			if ( isdefined( level.serverdvars ) )
			{
				a = [];
				a[ a.size ] = "assault";
				a[ a.size ] = "specops";
				a[ a.size ] = "heavygunner";
				a[ a.size ] = "demolitions";
				a[ a.size ] = "sniper";
				
				self notify( "menuresponse", game[ "menu_changeclass_" + self.pers[ "team" ] ], random( a ) );
				
				wait 0.5;
			}
			
			self notify( "menuresponse", game[ "menu_changeclass" ], self chooseRandomClass() );
		}
		
		self.bot_change_class = true;
		
		while ( isdefined( self.pers[ "team" ] ) && maps\mp\gametypes\_globallogic::isvalidclass( self.class ) && isdefined( self.bot_change_class ) )
		{
			wait .05;
		}
	}
}

/*
	Makes sure the bot is on a team.
*/
teamWatch()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		while ( !isdefined( self.pers[ "team" ] ) || !allowTeamChoice() )
		{
			wait .05;
		}
		
		wait 0.1;
		
		if ( self.team != "axis" && self.team != "allies" )
		{
			self notify( "menuresponse", game[ "menu_team" ], getdvar( "bots_team" ) );
		}
		
		while ( isdefined( self.pers[ "team" ] ) )
		{
			wait .05;
		}
	}
}

/*
	Updates the bot's difficulty variables.
*/
difficulty()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		if ( getdvarint( "bots_skill" ) != 9 )
		{
			switch ( self.pers[ "bots" ][ "skill" ][ "base" ] )
			{
				case 1:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.6;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 650;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 450;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 500;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 600;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 750;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.55;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 2500;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 1000;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.75;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 0;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.9;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 1;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 1.5;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 4;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 2;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_spinelower,j_ankle_le";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 0;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 30;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 20;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 0;
					break;
					
				case 2:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.55;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 550;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 380;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 1000;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 1250;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.52;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 3000;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.65;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 500;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.75;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0.75;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 1;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 3;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 1.5;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_spinelower,j_spinelower,j_ankle_ri,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 15;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 45;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 15;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 10;
					break;
					
				case 3:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.4;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 480;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 320;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 1000;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 2000;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 4000;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 2250;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 750;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.65;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0.65;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 0.75;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 2.5;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 1;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_spinelower,j_spinelower,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 20;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 20;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 50;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 25;
					break;
					
				case 4:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.3;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 420;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 280;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 1000;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 3000;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.47;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 5000;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 3350;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.35;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 1000;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 2;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 0.75;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_spinelower,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 30;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 25;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 55;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 35;
					break;
					
				case 5:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 360;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 240;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 2000;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 4000;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.45;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 7500;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 5000;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 1500;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.4;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0.35;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 0.35;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 1.5;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 40;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 35;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 60;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 50;
					break;
					
				case 6:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.2;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 300;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 200;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 2000;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 3000;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 5000;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.42;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 10000;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 7500;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.2;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 2000;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 1;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 0.25;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spinelower,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 50;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 45;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 65;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 10;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 75;
					break;
					
				case 7:
					self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.1;
					self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 250;
					self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 170;
					self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 2500;
					self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 4000;
					self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 7500;
					self.pers[ "bots" ][ "skill" ][ "fov" ] = 0.4;
					self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 15000;
					self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 10000;
					self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.05;
					self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 3000;
					self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.1;
					self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 0;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 0;
					self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 0;
					self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 0.05;
					self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_spineupper,j_head";
					self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5;
					self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5;
					
					self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 65;
					self.pers[ "bots" ][ "behavior" ][ "nade" ] = 65;
					self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 70;
					self.pers[ "bots" ][ "behavior" ][ "camp" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "follow" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 5;
					self.pers[ "bots" ][ "behavior" ][ "switch" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "class" ] = 2;
					self.pers[ "bots" ][ "behavior" ][ "jump" ] = 90;
					break;
			}
		}

		// Persona: persistent archetype per bot, nudges behavior every loop.
		self bot_get_persona();
		
		// Skill 9 tables never reset, so only nudge once there or it compounds.
		applyPersona = getdvarint( "bots_skill" ) != 9 || !isdefined( self.pers[ "bots" ][ "persona_applied" ] );
		self.pers[ "bots" ][ "persona_applied" ] = true;
		
		if ( applyPersona && self.pers[ "bots" ][ "persona" ] == "rusher" )
		{
			self.pers[ "bots" ][ "behavior" ][ "sprint" ] += 15;
			self.pers[ "bots" ][ "behavior" ][ "strafe" ] += 10;
			self.pers[ "bots" ][ "behavior" ][ "camp" ] = 0;
		}
		else if ( applyPersona && self.pers[ "bots" ][ "persona" ] == "anchor" )
		{
			self.pers[ "bots" ][ "behavior" ][ "camp" ] += 25;
			self.pers[ "bots" ][ "behavior" ][ "sprint" ] -= 15;
			self.pers[ "bots" ][ "behavior" ][ "crouch" ] += 10;
		}
		else if ( applyPersona && self.pers[ "bots" ][ "persona" ] == "objective" )
		{
			self.pers[ "bots" ][ "behavior" ][ "follow" ] -= 3;
			self.pers[ "bots" ][ "behavior" ][ "camp" ] = 0;
		}
		else if ( applyPersona )
		{
			self.pers[ "bots" ][ "behavior" ][ "follow" ] += 20;
			self.pers[ "bots" ][ "behavior" ][ "nade" ] += 10;
		}
		
		// Clamp: tables reset each loop for skills 1-8, but skill 9 never resets,
		// so bound everything to valid percentages.
		keys = getarraykeys( self.pers[ "bots" ][ "behavior" ] );
		for ( i = 0; i < keys.size; i++ )
		{
			k = keys[ i ];
			v = self.pers[ "bots" ][ "behavior" ][ k ];
			if ( k == "quickscope" || k == "initswitch" )
			{
				continue;
			}
			if ( v < 0 )
			{
				self.pers[ "bots" ][ "behavior" ][ k ] = 0;
			}
			else if ( v > 100 )
			{
				self.pers[ "bots" ][ "behavior" ][ k ] = 100;
			}
		}
		
		// Humanization values follow the skill base (added() only sets fallbacks).
		// Skill 9 is fully custom: derive once from its random base.
		if ( getdvarint( "bots_skill" ) != 9 || !isdefined( self.pers[ "bots" ][ "humanized" ] ) )
		{
			self.pers[ "bots" ][ "humanized" ] = true;
			base = 1;
			if ( isdefined( self.pers[ "bots" ][ "skill" ][ "base" ] ) )
			{
				base = self.pers[ "bots" ][ "skill" ][ "base" ];
			}
			self.pers[ "bots" ][ "skill" ][ "aim_jitter" ] = 0.55 - base * 0.05;
			self.pers[ "bots" ][ "skill" ][ "overshoot" ] = 28 - base * 3;
			self.pers[ "bots" ][ "skill" ][ "trigger_delay" ] = 80 - base * 10; // humans fire almost as soon as they are on target
			self.pers[ "bots" ][ "skill" ][ "switch_penalty" ] = 380 - base * 35;
			self.pers[ "bots" ][ "skill" ][ "periph_bonus" ] = 0.05 + base * 0.008;
			
			// Per-bot quirk, rolled once: how much of a moving target's lag this
			// player leads out. Some chronically under-lead, some nearly nail it.
			if ( !isdefined( self.pers[ "bots" ][ "lead_frac_roll" ] ) )
			{
				self.pers[ "bots" ][ "lead_frac_roll" ] = randomfloatrange( 0.35, 0.75 );
			}
			
			self.pers[ "bots" ][ "skill" ][ "lead_frac" ] = self.pers[ "bots" ][ "lead_frac_roll" ] + base * 0.04;
		}
		
		wait 5;
	}
}

/*
	Sets the bot difficulty.
*/
set_diff()
{
	rankVar = getdvarint( "bots_skill" );
	
	switch ( rankVar )
	{
		case 0:
			self.pers[ "bots" ][ "skill" ][ "base" ] = Round( random_normal_distribution( 3.5, 1.75, 1, 7 ) );
			break;
			
		case 8:
			break;
			
		case 9:
			self.pers[ "bots" ][ "skill" ][ "base" ] = randomintrange( 1, 7 );
			self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.05 * randomintrange( 1, 20 );
			self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 50 * randomint( 100 );
			self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 50 * randomint( 100 );
			self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 50 * randomint( 100 );
			self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 50 * randomint( 100 );
			self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 50 * randomint( 100 );
			self.pers[ "bots" ][ "skill" ][ "fov" ] = randomfloatrange( -1, 1 );
			
			randomNum = randomintrange( 500, 25000 );
			self.pers[ "bots" ][ "skill" ][ "dist_start" ] = randomNum;
			self.pers[ "bots" ][ "skill" ][ "dist_max" ] = randomNum * 2;
			
			self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0.05 * randomint( 20 );
			self.pers[ "bots" ][ "skill" ][ "help_dist" ] = randomintrange( 500, 25000 );
			self.pers[ "bots" ][ "skill" ][ "semi_time" ] = randomfloatrange( 0.05, 1 );
			self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = randomfloatrange( 0.05, 1 );
			self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = randomfloatrange( 0.05, 1 );
			self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = randomfloatrange( 0.05, 1 );
			self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = randomfloatrange( 0.05, 1 );
			self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_head,j_spineupper,j_ankle_ri,j_ankle_le";
			
			self.pers[ "bots" ][ "behavior" ][ "strafe" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "nade" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "sprint" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "camp" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "follow" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "crouch" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "switch" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "class" ] = randomint( 100 );
			self.pers[ "bots" ][ "behavior" ][ "jump" ] = randomint( 100 );
			break;
			
		default:
			self.pers[ "bots" ][ "skill" ][ "base" ] = rankVar;
			break;
	}
}

/*
	Sets the bot's classes.
*/
set_class( rankxp )
{
	primaryGroups = [];
	primaryGroups[ 0 ] = "weapon_lmg";
	primaryGroups[ 1 ] = "weapon_smg";
	primaryGroups[ 2 ] = "weapon_shotgun";
	primaryGroups[ 3 ] = "weapon_sniper";
	primaryGroups[ 4 ] = "weapon_assault";
	secondaryGroups = [];
	secondaryGroups[ 0 ] = "weapon_pistol";
	
	rank = self maps\mp\gametypes\_rank::getrankforxp( rankxp ) + 1;
	persona = self bot_get_persona();
	
	if ( randomfloatrange( 0, 1 ) < ( ( rank / level.maxrank ) + 0.1 ) )
	{
		self.pers[ "bots" ][ "behavior" ][ "quickscope" ] = true;
	}
	
	for ( i = 0; i < 5; i++ )
	{
		primary = get_random_weapon( primaryGroups, rank, persona );
		att1 = get_random_attachment( primary, rank );
		
		perk2 = get_random_perk( "perk2", rank );
		
		if ( perk2 != "specialty_twoprimaries" )
		{
			secondary = get_random_weapon( secondaryGroups, rank, persona );
		}
		else
		{
			secondary = "";
			
			while ( secondary == "" )
			{
				secondary = get_random_weapon( primaryGroups, rank, persona );
				
				if ( primary == secondary )
				{
					secondary = "";
				}
			}
		}
		
		att2 = get_random_attachment( secondary, rank );
		perk1 = get_random_perk( "perk1", rank, att1, att2 );
		
		perk3 = get_random_perk( "perk3", rank );
		gren = get_random_grenade( perk1 );
		camo = randomint( 8 );
		
		self setstat ( 200 + ( i * 10 ) + 1, level.weaponreferencetoindex[ primary ] );
		self setstat ( 200 + ( i * 10 ) + 2, level.weaponattachmentreferencetoindex[ att1 ] );
		self setstat ( 200 + ( i * 10 ) + 3, level.weaponreferencetoindex[ secondary ] );
		self setstat ( 200 + ( i * 10 ) + 4, level.weaponattachmentreferencetoindex[ att2 ] );
		self setstat ( 200 + ( i * 10 ) + 5, level.perkreferencetoindex[ perk1 ] );
		self setstat ( 200 + ( i * 10 ) + 6, level.perkreferencetoindex[ perk2 ] );
		self setstat ( 200 + ( i * 10 ) + 7, level.perkreferencetoindex[ perk3 ] );
		self setstat ( 200 + ( i * 10 ) + 8, level.weaponreferencetoindex[ gren ] );
		self setstat ( 200 + ( i * 10 ) + 9, camo );
	}
}

/*
	Returns a random attachment for the bot.
*/
get_random_attachment( weapon, rank )
{
	if ( randomfloatrange( 0, 1 ) > ( 0.1 + ( rank / level.maxrank ) ) )
	{
		return "none";
	}
	
	reasonable = getdvarint( "bots_loadout_reasonable" );
	op = getdvarint( "bots_loadout_allow_op" );
	
	id = level.tbl_weaponids[ level.weaponreferencetoindex[ weapon ] ];
	atts = strtok( id[ "attachment" ], " " );
	atts[ atts.size ] = "none";
	metaList = undefined;
	
	if ( getdvarint( "bots_loadout_meta" ) )
	{
		metaList = bot_meta_attachments( id[ "group" ] );
	}
	
	for ( tries = 0;; tries++ )
	{
		att = atts[ randomint( atts.size ) ];
		
		// Meta pick first; only kept if this weapon actually has it.
		if ( isdefined( metaList ) && tries < 20 )
		{
			att = bot_weighted_pick( metaList, undefined );
			
			if ( att != "none" && !bot_list_has( atts, att ) )
			{
				continue;
			}
		}
		
		if ( reasonable )
		{
			switch ( att )
			{
				case "acog":
					if ( weapon != "m40a3" )
					{
						continue;
					}
					
					break;
			}
		}
		
		if ( !op )
		{
			if ( att == "gl" )
			{
				continue;
			}
		}
		
		return att;
	}
}

/*
	Returns a random perk for the bot.
*/
get_random_perk( perkslot, rank, att1, att2 )
{
	if ( isdefined( att1 ) && isdefined( att2 ) && ( att1 == "grip" || att1 == "gl" || att2 == "grip" || att2 == "gl" ) )
	{
		return "specialty_null";
	}
	
	reasonable = getdvarint( "bots_loadout_reasonable" );
	op = getdvarint( "bots_loadout_allow_op" );
	
	keys = getarraykeys( level.tbl_perkdata );
	metaList = undefined;
	
	if ( getdvarint( "bots_loadout_meta" ) )
	{
		metaList = bot_meta_perks( perkslot );
	}
	
	for ( tries = 0;; tries++ )
	{
		if ( isdefined( metaList ) && tries < 30 )
		{
			ref = bot_weighted_pick( metaList, undefined );
		}
		else
		{
			id = level.tbl_perkdata[ keys[ randomint( keys.size ) ] ];
			
			if ( !isdefined( id ) || !isdefined( id[ "perk_num" ] ) )
			{
				continue;
			}
			
			if ( perkslot != id[ "perk_num" ] )
			{
				continue;
			}
			
			ref = id[ "reference_full" ];
			
			if ( ref == "specialty_null" && randomint( 100 ) < 95 )
			{
				continue;
			}
		}
		
		if ( reasonable )
		{
			switch ( ref )
			{
				case "specialty_parabolic":
				case "specialty_holdbreath":
				case "specialty_explosivedamage":
				case "specialty_twoprimaries":
					continue;
			}
		}
		
		if ( !op )
		{
			switch ( ref )
			{
				case "specialty_armorvest":
				case "specialty_pistoldeath":
				case "specialty_grenadepulldeath":
				case "specialty_weapon_rpg":
					continue;
			}
		}
		
		if ( !isItemUnlocked( ref, rank ) )
		{
			continue;
		}
		
		return ref;
	}
}

/*
	Returns a random grenade for the bot.
*/
get_random_grenade( perk1 )
{
	possibles = [];
	possibles[ 0 ] = "flash_grenade";
	possibles[ 1 ] = "smoke_grenade";
	possibles[ 2 ] = "concussion_grenade";
	
	reasonable = getdvarint( "bots_loadout_reasonable" );
	
	for ( ;; )
	{
		possible = possibles[ randomint( possibles.size ) ];
		
		if ( getdvarint( "bots_loadout_meta" ) )
		{
			// flash and stun dominate pubs; smoke is niche
			possible = bot_weighted_pick( "flash_grenade:45,concussion_grenade:40,smoke_grenade:15", undefined );
		}
		
		if ( reasonable )
		{
			switch ( possible )
			{
				case "smoke_grenade":
					continue;
			}
		}
		
		if ( perk1 == "specialty_specialgrenade" && possible == "smoke_grenade" )
		{
			continue;
		}
		
		return possible;
	}
}

/*
	Returns a random weapon for the bot.
*/
get_random_weapon( groups, rank, persona )
{
	reasonable = getdvarint( "bots_loadout_reasonable" );
	op = getdvarint( "bots_loadout_allow_op" );
	
	keys = getarraykeys( level.tbl_weaponids );
	metaList = undefined;
	
	if ( getdvarint( "bots_loadout_meta" ) )
	{
		metaList = bot_meta_weapons( groups );
	}
	
	for ( tries = 0;; tries++ )
	{
		id = level.tbl_weaponids[ keys[ randomint( keys.size ) ] ];
		
		// Meta pick first; the checks below still apply (group, filters, unlocks).
		if ( isdefined( metaList ) && tries < 30 )
		{
			ref = bot_weighted_pick( metaList, persona );
			
			if ( !isdefined( level.weaponreferencetoindex[ ref ] ) )
			{
				continue;
			}
			
			id = level.tbl_weaponids[ level.weaponreferencetoindex[ ref ] ];
		}
		
		if ( !isdefined( id ) )
		{
			continue;
		}
		
		group = id[ "group" ];
		inGroup = false;
		
		for ( i = groups.size - 1; i >= 0; i-- )
		{
			if ( groups[ i ] == group )
			{
				inGroup = true;
			}
		}
		
		if ( !inGroup )
		{
			continue;
		}
		
		ref = id[ "reference" ];
		
		if ( reasonable )
		{
			switch ( ref )
			{
				case "skorpion":
				case "uzi":
				case "m21":
				case "dragunov":
				case "saw":
				case "mp44":
				case "m14":
				case "g3":
				case "m1014":
					continue;
			}
		}
		
		if ( !op )
		{
			if ( ref == "rpg" )
			{
				continue;
			}
		}
		
		if ( !isItemUnlocked( ref, rank ) )
		{
			continue;
		}
		
		return ref;
	}
}

/*
	Restores the identity of a bot carried over from the last map.
*/
bot_apply_carry()
{
	if ( !isdefined( self.bot_carry ) || self.bot_carry.size < 5 )
	{
		return;
	}
	
	c = self.bot_carry;
	
	if ( c[ 1 ] != "-" )
	{
		self.pers[ "bots" ][ "persona" ] = c[ 1 ];
	}
	
	// keep the same skill when skill is the random mix
	if ( c[ 2 ] != "-" && getdvarint( "bots_skill" ) == 0 )
	{
		self.pers[ "bots" ][ "skill" ][ "base" ] = int( c[ 2 ] );
	}
	
	if ( c[ 3 ] != "-" )
	{
		self.pers[ "bots" ][ "chat_lang" ] = c[ 3 ];
	}
	
	if ( c[ 4 ] != "-" )
	{
		self.pers[ "bots" ][ "lead_frac_roll" ] = float_old( c[ 4 ] );
	}
}

/*
	Sessions and leaves: people drift off after a while (leaving after a death,
	not mid-fight) and some rage quit after a bad run.
*/
bot_lifecycle()
{
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	if ( !getdvarint( "bots_lobby_human" ) )
	{
		return;
	}
	
	deathsNoKill = 0;
	wantsLeave = false;
	
	for ( ;; )
	{
		ret = self waittill_any_timeout( 60, "death", "killed_enemy" );
		
		if ( ret == "killed_enemy" )
		{
			deathsNoKill = 0;
			continue;
		}
		
		if ( ret == "death" )
		{
			deathsNoKill++;
			
			// rage quits are memorable because they're rare: one per ~10 min server-wide
			if ( deathsNoKill >= 7 && randomint( 100 ) < 6 && ( !isdefined( level.bot_last_ragequit ) || gettime() - level.bot_last_ragequit > 600000 ) )
			{
				level.bot_last_ragequit = gettime();
				self thread bot_leave( "rage_leave", 50 );
				return;
			}
			
			if ( wantsLeave )
			{
				self thread bot_leave( "leave", 35 );
				return;
			}
			
			continue;
		}
		
		// ~45 min average session: decide to leave, then go at the next death
		if ( randomint( 1000 ) < 22 )
		{
			wantsLeave = true;
		}
	}
}

/*
	Says bye (sometimes) and disconnects.
*/
bot_leave( cat, chance )
{
	self endon( "disconnect" );
	
	self BotTelemetryEvent( "lobby:" + cat );
	self maps\mp\bots\_bot_chat::bot_chat_human( cat, undefined, chance );
	wait randomfloatrange( 2.5, 7 );
	kick( self getentitynumber(), "EXE_DISCONNECTED" );
}

/*
	A waypoint's facing, or a random direction when it has none (some typed
	waypoints are missing angles; using them undefined is a fatal script error).
*/
bot_wp_forward( wp )
{
	if ( isdefined( wp.angles ) )
	{
		return anglestoforward( wp.angles );
	}
	
	return anglestoforward( ( 0, randomint( 360 ), 0 ) );
}

/*
	The bot's persistent archetype (rolled once, kept across maps).
*/
bot_get_persona()
{
	if ( !isdefined( self.pers[ "bots" ][ "persona" ] ) )
	{
		// real S&D archetypes (48 demo sessions): mobile 42%, careful rifleman 52%, camper/prone 6%
		self.pers[ "bots" ][ "persona" ] = bot_weighted_pick( "rusher:42,objective:26,support:26,anchor:6", undefined );
	}
	
	return self.pers[ "bots" ][ "persona" ];
}

/*
	Picks from "ref:weight[:class],..." by weight. Entries with a class tag
	(a/s/l/g/r = assault/smg/lmg/shotgun/sniper) get the persona's multiplier.
*/
bot_weighted_pick( list, persona )
{
	entries = strtok( list, "," );
	weights = [];
	total = 0;
	
	for ( i = 0; i < entries.size; i++ )
	{
		parts = strtok( entries[ i ], ":" );
		w = int( parts[ 1 ] ) * 10;
		
		if ( isdefined( persona ) && parts.size > 2 )
		{
			w = int( w * bot_persona_class_mult( persona, parts[ 2 ] ) );
		}
		
		weights[ i ] = w;
		total += w;
	}
	
	roll = randomint( total );
	
	for ( i = 0; i < entries.size; i++ )
	{
		if ( roll < weights[ i ] )
		{
			parts = strtok( entries[ i ], ":" );
			return parts[ 0 ];
		}
		
		roll -= weights[ i ];
	}
	
	parts = strtok( entries[ 0 ], ":" );
	return parts[ 0 ];
}

/*
	How much a persona favors a weapon class.
*/
bot_persona_class_mult( persona, cls )
{
	switch ( persona )
	{
		case "rusher":
			if ( cls == "s" )
			{
				return 2.5;
			}
			
			if ( cls == "g" )
			{
				return 3;
			}
			
			if ( cls == "r" )
			{
				return 0.2;
			}
			
			break;
			
		case "anchor":
			if ( cls == "r" )
			{
				return 3;
			}
			
			if ( cls == "l" )
			{
				return 2;
			}
			
			if ( cls == "s" )
			{
				return 0.5;
			}
			
			break;
			
		case "support":
			if ( cls == "l" )
			{
				return 2;
			}
			
			break;
			
		case "objective":
			if ( cls == "a" )
			{
				return 1.3;
			}
			
			break;
	}
	
	return 1;
}

/*
	Returns true if the array contains the value.
*/
bot_list_has( arr, value )
{
	for ( i = 0; i < arr.size; i++ )
	{
		if ( arr[ i ] == value )
		{
			return true;
		}
	}
	
	return false;
}

/*
	Weapon weights from human public-server kill stats (UltraStats, ~2.2M kills)
	blended with forum meta: ARs ~52%, SMGs ~26%, snipers ~9%, LMGs ~10%.
*/
bot_meta_weapons( groups )
{
	if ( bot_list_has( groups, "weapon_pistol" ) )
	{
		return "deserteagle:30,deserteaglegold:10,beretta:25,usp:20,colt45:15";
	}
	
	return "m16:16:a,m4:14:a,ak47:12:a,g3:6:a,g36c:2:a,m14:1:a,mp44:1:a," +
		"p90:9:s,mp5:9:s,ak74u:6:s,uzi:1:s,skorpion:1:s," +
		"rpd:7:l,saw:2:l,m60e4:1:l," +
		"winchester1200:1:g,m1014:2:g," +
		"m21:3:r,m40a3:2:r,dragunov:2:r,remington700:1:r,barrett:1:r";
}

/*
	Attachment weights per weapon group: red dot and silencer rule pubs,
	ACOG is rare outside snipers, a few noob-tubers.
*/
bot_meta_attachments( group )
{
	switch ( group )
	{
		case "weapon_assault":
			return "reflex:40,silencer:25,none:22,acog:6,gl:7";
			
		case "weapon_smg":
			return "silencer:40,reflex:30,none:27,acog:3";
			
		case "weapon_lmg":
			return "none:45,reflex:35,grip:15,acog:5";
			
		case "weapon_shotgun":
			return "none:60,reflex:20,grip:20";
			
		case "weapon_sniper":
			return "none:60,silencer:30,acog:10";
			
		case "weapon_pistol":
			return "none:75,silencer:25";
	}
	
	return "none:1";
}

/*
	Perk weights: Stopping Power dominates tier 2; Bandolier/Frag x3/Claymore
	tier 1; Deep Impact/Steady Aim/Dead Silence tier 3, plus the hated
	Juggernaut, Martyrdom and Last Stand at pub-typical rates.
*/
bot_meta_perks( perkslot )
{
	switch ( perkslot )
	{
		case "perk1":
			return "specialty_extraammo:22,specialty_fraggrenade:22,specialty_weapon_claymore:20,specialty_weapon_c4:14,specialty_specialgrenade:8,specialty_weapon_rpg:8,specialty_detectexplosive:6";
			
		case "perk2":
			return "specialty_bulletdamage:52,specialty_armorvest:16,specialty_gpsjammer:16,specialty_fastreload:7,specialty_rof:5,specialty_twoprimaries:2,specialty_explosivedamage:2";
			
		case "perk3":
			return "specialty_bulletpenetration:22,specialty_bulletaccuracy:18,specialty_quieter:16,specialty_longersprint:12,specialty_pistoldeath:12,specialty_grenadepulldeath:10,specialty_holdbreath:6,specialty_parabolic:4";
	}
	
	return "specialty_null:1";
}

/*
	Gets the prestige
*/
bot_get_prestige()
{
	p_dvar = getdvarint( "bots_loadout_prestige" );
	p = 0;
	
	if ( p_dvar == -1 )
	{
		for ( i = 0; i < level.players.size; i++ )
		{
			player = level.players[ i ];
			
			if ( !isdefined( player.team ) )
			{
				continue;
			}
			
			if ( player is_bot() )
			{
				continue;
			}
			
			p = player getstat( int( tablelookup( "mp/playerStatsTable.csv", 1, "plevel", 0 ) ) );
			break;
		}
	}
	else if ( p_dvar == -2 )
	{
		p = randomint( 12 );
	}
	else
	{
		p = p_dvar;
	}
	
	return p;
}

/*
	Gets an exp amount for the bot that is nearish the host's xp.
*/
bot_get_rank()
{
	rank = 1;
	rank_dvar = getdvarint( "bots_loadout_rank" );
	
	if ( rank_dvar == -1 )
	{
		ranks = [];
		bot_ranks = [];
		human_ranks = [];
		
		for ( i = level.players.size - 1; i >= 0; i-- )
		{
			player = level.players[ i ];
			
			if ( player == self )
			{
				continue;
			}
			
			if ( !isdefined( player.pers[ "rank" ] ) )
			{
				continue;
			}
			
			if ( player is_bot() )
			{
				bot_ranks[ bot_ranks.size ] = player.pers[ "rank" ];
			}
			else
			{
				human_ranks[ human_ranks.size ] = player.pers[ "rank" ];
			}
		}
		
		if ( !human_ranks.size )
		{
			human_ranks[ human_ranks.size ] = Round( random_normal_distribution( 35, 15, 0, level.maxrank ) );
		}
		
		human_avg = array_average( human_ranks );
		
		while ( bot_ranks.size + human_ranks.size < 5 )
		{
			// add some random ranks for better random number distribution
			rank = human_avg + randomintrange( -10, 10 );
			human_ranks[ human_ranks.size ] = rank;
		}
		
		ranks = array_combine( human_ranks, bot_ranks );
		
		avg = array_average( ranks );
		s = array_std_deviation( ranks, avg );
		
		rank = Round( random_normal_distribution( avg, s, 0, level.maxrank ) );
	}
	else if ( rank_dvar == 0 )
	{
		rank = Round( random_normal_distribution( 35, 15, 0, level.maxrank ) );
	}
	else
	{
		rank = Round( random_normal_distribution( rank_dvar, 5, 0, level.maxrank ) );
	}
	
	return maps\mp\gametypes\_rank::getrankinfominxp( rank );
}

/*
	When the bot spawns.
*/
onSpawned()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "spawned_player" );
		
		if ( randomint( 100 ) <= self.pers[ "bots" ][ "behavior" ][ "class" ] )
		{
			self.bot_change_class = undefined;
		}
		
		self.bot_lock_goal = false;
		self.help_time = undefined;
		self.bot_was_follow_script_update = undefined;
		
		if ( getdvarint( "bots_play_obj" ) )
		{
			self thread bot_dom_cap_think();
		}
	}
}

/*
	When the bot spawned, after the difficulty wait. Start the logic for the bot.
*/
onBotSpawned()
{
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	for ( ;; )
	{
		self waittill( "bot_spawned" );
		
		self thread start_bot_threads();
	}
}

/*
	Starts all the bot thinking
*/
start_bot_threads()
{
	self endon( "disconnect" );
	level endon( "game_ended" );
	self endon( "death" );
	
	while ( level.inprematchperiod )
	{
		wait 0.05;
	}
	
	// inventory usage
	if ( getdvarint( "bots_play_killstreak" ) )
	{
		self thread bot_killstreak_think();
	}
	
	self thread bot_weapon_think();
	self thread doReloadCancel();
	
	// script targeting
	if ( getdvarint( "bots_play_target_other" ) )
	{
		self thread bot_target_vehicle();
		self thread bot_equipment_kill_think();
	}
	
	// awareness
	self thread bot_revenge_think();
	self thread bot_uav_think();
	self thread bot_listen_to_steps();
	self thread follow_target();
	
	// camp and follow
	if ( getdvarint( "bots_play_camp" ) )
	{
		self thread bot_think_follow();
		self thread bot_think_camp();
	}
	
	// nades
	if ( getdvarint( "bots_play_nade" ) )
	{
		self thread bot_use_tube_think();
		self thread bot_use_grenade_think();
		self thread bot_spawn_nade();
		self thread bot_weapon_watchdog();
		self thread bot_use_equipment_think();
		self thread bot_watch_think_mw2();
	}
	
	// obj
	if ( getdvarint( "bots_play_obj" ) )
	{
		self thread bot_dom_def_think();
		self thread bot_dom_spawn_kill_think();
		
		self thread bot_hq();
		
		self thread bot_sab();
		
		self thread bot_sd_defenders();
		self thread bot_sd_attackers();
	}
}

/*
	Increments the number of bots approching the obj, decrements when needed
	Used for preventing too many bots going to one obj, or unreachable objs
*/
bot_inc_bots( obj, unreach )
{
	level endon( "game_ended" );
	self endon( "bot_inc_bots" );
	
	if ( !isdefined( obj ) )
	{
		return;
	}
	
	if ( !isdefined( obj.bots ) )
	{
		obj.bots = 0;
	}
	
	obj.bots++;
	
	ret = self waittill_any_return( "death", "disconnect", "bad_path", "goal", "new_goal" );
	
	if ( isdefined( obj ) && ( ret != "bad_path" || !isdefined( unreach ) ) )
	{
		obj.bots--;
	}
}

/*
	Watches when the bot is touching the obj and calls 'goal'
*/
bots_watch_touch_obj( obj )
{
	self endon ( "death" );
	self endon ( "disconnect" );
	self endon ( "bad_path" );
	self endon ( "goal" );
	self endon ( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !isdefined( obj ) )
		{
			self notify( "bad_path" );
			return;
		}
		
		if ( self istouching( obj ) )
		{
			self notify( "goal" );
			return;
		}
	}
}

/*
	Watches while the obj is being carried, calls 'goal' when complete
*/
bot_escort_obj( obj, carrier )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !isdefined( obj ) )
		{
			break;
		}
		
		if ( !isdefined( obj.carrier ) || carrier == obj.carrier )
		{
			break;
		}
	}
	
	self notify( "goal" );
}

/*
	Watches while the obj is not being carried, calls 'goal' when complete
*/
bot_get_obj( obj )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !isdefined( obj ) )
		{
			break;
		}
		
		if ( isdefined( obj.carrier ) )
		{
			break;
		}
	}
	
	self notify( "goal" );
}

/*
	bots will defend their site from a planter/defuser
*/
bot_defend_site( site )
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !site isInUse() )
		{
			break;
		}
	}
	
	self notify( "bad_path" );
}

/*
	Bots will go plant the bomb
*/
bot_go_plant( plant )
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( level.bombplanted )
		{
			break;
		}
		
		if ( self istouching( plant.trigger ) )
		{
			break;
		}
	}
	
	if ( level.bombplanted )
	{
		self notify( "bad_path" );
	}
	else
	{
		self notify( "goal" );
	}
}

/*
	Bots will go defuse the bomb
*/
bot_go_defuse( plant )
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( !level.bombplanted )
		{
			break;
		}
		
		if ( self istouching( plant.trigger ) )
		{
			break;
		}
	}
	
	if ( !level.bombplanted )
	{
		self notify( "bad_path" );
	}
	else
	{
		self notify( "goal" );
	}
}

/*
	Waits for the bot to stop moving
*/
bot_wait_stop_move()
{
	while ( !self isonground() || lengthsquared( self getvelocity() ) > 1 )
	{
		wait 0.25;
	}
}

/*
	Fires the bots weapon until told to stop
*/
fire_current_weapon()
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "weapon_change" );
	self endon( "stop_firing_weapon" );
	
	for ( ;; )
	{
		self thread BotPressAttack( 0.05 );
		wait 0.1;
	}
}

/*
	Fires the bots c4
*/
fire_c4()
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "weapon_change" );
	self endon( "stop_firing_weapon" );
	
	for ( ;; )
	{
		self thread BotPressADS( 0.05 );
		wait 0.1;
	}
}

/*
	Changes to the weap
*/
changeToWeapon( weap )
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	if ( !self hasweapon( weap ) )
	{
		return false;
	}
	
	self BotBuiltinBotWeapon( weap );
	self switchtoweapon( weap );
	
	if ( self getcurrentweapon() == weap )
	{
		return true;
	}
	
	self waittill_any_timeout( 5, "weapon_change" );
	
	return ( self getcurrentweapon() == weap );
}

/*
	Bots throw the grenade
*/
botThrowGrenade( nade, time )
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	if ( !self getammocount( nade ) )
	{
		return false;
	}
	
	if ( nade != "frag_grenade_mp" )
	{
		self thread BotPressSmoke( time );
	}
	else
	{
		self thread BotPressFrag( time );
	}
	
	ret = self waittill_any_timeout( 5, "grenade_fire" );
	
	return ( ret == "grenade_fire" );
}

/*
	Gets the object thats the closest in the array
*/
bot_array_nearest_curorigin( array )
{
	result = undefined;
	
	for ( i = 0; i < array.size; i++ )
	{
		if ( !isdefined( result ) || distancesquared( self.origin, array[ i ].curorigin ) < distancesquared( self.origin, result.curorigin ) )
		{
			result = array[ i ];
		}
	}
	
	return result;
}

/*
	Clears goal when events death
*/
stop_go_target_on_death( tar )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "new_goal" );
	self endon( "bad_path" );
	self endon( "goal" );
	
	tar waittill_either( "death", "disconnect" );
	
	self ClearScriptGoal();
}

/*
	Bot logic for bot determining to camp.
*/
bot_think_camp_loop()
{
	campSpot = getWaypointForIndex( random( self waypointsNear( getWaypointsOfType( "camp" ), 1024 ) ) );
	
	if ( !isdefined( campSpot ) )
	{
		return;
	}
	
	self SetScriptGoal( campSpot.origin, 16 );
	
	time = randomintrange( 30, 90 );
	
	self BotNotifyBotEvent( "camp", "go", campSpot, time );
	
	ret = self waittill_any_return( "new_goal", "goal", "bad_path" );
	
	if ( ret != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	if ( ret != "goal" )
	{
		return;
	}
	
	self BotNotifyBotEvent( "camp", "start", campSpot, time );
	
	self thread killCampAfterTime( time );
	// some camp waypoints have no facing: watch a random direction then
	campAngles = ( 0, randomint( 360 ), 0 );
	
	if ( isdefined( campSpot.angles ) )
	{
		campAngles = campSpot.angles;
	}
	
	self CampAtSpot( campSpot.origin, campSpot.origin + anglestoforward( campAngles ) * 2048 );
	
	self BotNotifyBotEvent( "camp", "stop", campSpot, time );
}

/*
	Bot logic for bot determining to camp.
*/
bot_think_camp()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait randomintrange( 4, 7 );
		
		if ( self HasScriptGoal() || self.bot_lock_goal || self HasScriptAimPos() )
		{
			continue;
		}
		
		if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "camp" ] )
		{
			continue;
		}
		
		self bot_think_camp_loop();
	}
}

/*
	Kills the camping thread when time
*/
killCampAfterTime( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "kill_camp_bot" );
	
	timeleft = maps\mp\gametypes\_globallogic::gettimeremaining() / 1000;
	
	while ( time > 0 && timeleft >= 60 )
	{
		wait 1;
		timeleft = maps\mp\gametypes\_globallogic::gettimeremaining() / 1000;
		time--;
	}
	
	wait 0.05;

	self ClearScriptGoal();
	self ClearScriptAimPos();
	
	self notify( "kill_camp_bot" );
}

/*
	Kills the camping thread when ent gone
*/
killCampAfterEntGone( ent )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "kill_camp_bot" );
	
	for ( ;; )
	{
		wait 0.05;
		
		if ( !isdefined( ent ) )
		{
			break;
		}
	}
	
	self ClearScriptGoal();
	self ClearScriptAimPos();
	
	self notify( "kill_camp_bot" );
}

/*
	Camps at the spot
*/
CampAtSpot( origin, anglePos )
{
	self endon( "kill_camp_bot" );
	
	self SetScriptGoal( origin, 64 );
	
	if ( isdefined( anglePos ) )
	{
		self SetScriptAimPos( anglePos );
	}
	
	self waittill( "new_goal" );
	self ClearScriptAimPos();
	
	self notify( "kill_camp_bot" );
}

/*
	Bot logic for bot determining to follow another player.
*/
bot_think_follow_loop()
{
	follows = [];
	distSq = self.pers[ "bots" ][ "skill" ][ "help_dist" ] * self.pers[ "bots" ][ "skill" ][ "help_dist" ];
	
	for ( i = level.players.size - 1; i >= 0; i-- )
	{
		player = level.players[ i ];
		
		if ( !player IsPlayerModelOK() )
		{
			continue;
		}
		
		if ( player == self )
		{
			continue;
		}
		
		if ( !isalive( player ) )
		{
			continue;
		}
		
		if ( player.team != self.team )
		{
			continue;
		}
		
		// Avoid conga lines: do not follow a bot who is already following.
		if ( player is_bot() )
		{
			if ( player HasScriptAimPos() )
			{
				continue;
			}
		}
		
		if ( distancesquared( player.origin, self.origin ) > distSq )
		{
			continue;
		}
		
		follows[ follows.size ] = player;
	}
	
	toFollow = random( follows );
	
	if ( !isdefined( toFollow ) )
	{
		return;
	}
	
	time = randomintrange( 10, 20 );
	
	self BotNotifyBotEvent( "follow", "start", toFollow, time );
	
	self thread killFollowAfterTime( time );
	self followPlayer( toFollow );
	
	self BotNotifyBotEvent( "follow", "stop", toFollow, time );
}

/*
	Bot logic for bot determining to follow another player.
*/
bot_think_follow()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait randomintrange( 3, 5 );
		
		if ( self HasScriptGoal() || self.bot_lock_goal || self HasScriptAimPos() )
		{
			continue;
		}
		
		if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "follow" ] )
		{
			continue;
		}
		
		if ( !level.teambased )
		{
			continue;
		}
		
		self bot_think_follow_loop();
	}
}

/*
	Kills follow when new goal
*/
watchForFollowNewGoal()
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "kill_follow_bot" );
	
	for ( ;; )
	{
		self waittill( "new_goal" );
		
		if ( !isdefined( self.bot_was_follow_script_update ) )
		{
			break;
		}
	}
	
	self ClearScriptAimPos();
	self notify( "kill_follow_bot" );
}

/*
	Kills follow when time
*/
killFollowAfterTime( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "kill_follow_bot" );
	
	wait time;
	
	self ClearScriptGoal();
	self ClearScriptAimPos();
	self notify( "kill_follow_bot" );
}

/*
	Determine bot to follow a player
*/
followPlayer( who )
{
	self endon( "kill_follow_bot" );
	
	self thread watchForFollowNewGoal();
	
	for ( ;; )
	{
		wait 0.05;
		
		if ( !isdefined( who ) || !isalive( who ) )
		{
			break;
		}
		
		// Overwatch the leader's lane, not the back of their head.
		leadAngles = who getplayerangles();
		leadForward = anglestoforward( leadAngles );
		self SetScriptAimPos( who.origin + leadForward * 500 + ( 0, 0, 42 ) );
		myGoal = self GetScriptGoal();
		
		if ( isdefined( myGoal ) && distancesquared( myGoal, who.origin ) < 200 * 200 )
		{
			continue;
		}
		
		self.bot_was_follow_script_update = true;
		// Lateral spacing so followers do not stack on the leader.
		side = anglestoforward( ( 0, leadAngles[ 1 ] + 90, 0 ) );
		back = anglestoforward( ( 0, leadAngles[ 1 ] + 180, 0 ) );
		followPos = who.origin + side * randomintrange( -150, 150 ) + back * randomintrange( 80, 200 );
		self SetScriptGoal( followPos, 64 );
		waittillframeend;
		self.bot_was_follow_script_update = undefined;
		
		self waittill_either( "goal", "bad_path" );
	}
	
	self ClearScriptGoal();
	self ClearScriptAimPos();
	
	self notify( "kill_follow_bot" );
}

/*
	Bots thinking of using a noobtube
*/
bot_use_tube_think_loop( data )
{
	if ( data.dofastcontinue )
	{
		data.dofastcontinue = false;
	}
	else
	{
		wait randomintrange( 3, 7 );
		
		chance = self.pers[ "bots" ][ "behavior" ][ "nade" ] / 2;
		
		if ( chance > 20 )
		{
			chance = 20;
		}
		
		if ( randomint( 100 ) > chance )
		{
			return;
		}
	}
	
	tube = self getValidTube();
	
	if ( !isdefined( tube ) )
	{
		return;
	}
	
	if ( self HasThreat() || self HasScriptAimPos() )
	{
		return;
	}
	
	if ( self BotIsFrozen() )
	{
		return;
	}
	
	if ( self IsBotFragging() || self IsBotSmoking() )
	{
		return;
	}
	
	if ( self isDefusing() || self isPlanting() )
	{
		return;
	}
	
	if ( self inLastStand() )
	{
		return;
	}
	
	loc = undefined;
	
	if ( !self nearAnyOfWaypoints( 128, getWaypointsOfType( "tube" ) ) )
	{
		tubeWp = getWaypointForIndex( random( self waypointsNear( getWaypointsOfType( "tube" ), 1024 ) ) );
		
		myEye = self geteye();
		
		if ( !isdefined( tubeWp ) || self HasScriptGoal() || self.bot_lock_goal )
		{
			traceForward = bullettrace( myEye, myEye + anglestoforward( self getplayerangles() ) * 900 * 5, false, self );
			
			loc = traceForward[ "position" ];
			dist = distancesquared( self.origin, loc );
			
			if ( dist < level.bots_mingrenadedistance || dist > level.bots_maxgrenadedistance * 5 )
			{
				return;
			}
			
			if ( !bullettracepassed( self.origin + ( 0, 0, 5 ), self.origin + ( 0, 0, 2048 ), false, self ) )
			{
				return;
			}
			
			if ( !bullettracepassed( loc + ( 0, 0, 5 ), loc + ( 0, 0, 2048 ), false, self ) )
			{
				return;
			}
			
			loc += ( 0, 0, dist / 16000 );
		}
		else
		{
			self BotNotifyBotEvent( "tube", "go", tubeWp, tube );
			
			self SetScriptGoal( tubeWp.origin, 16 );
			
			ret = self waittill_any_return( "new_goal", "goal", "bad_path" );
			
			if ( ret != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			if ( ret != "goal" )
			{
				return;
			}
			
			data.dofastcontinue = true;
			return;
		}
	}
	else
	{
		tubeWp = getWaypointForIndex( self getNearestWaypointOfWaypoints( getWaypointsOfType( "tube" ) ) );
		loc = tubeWp.origin + bot_wp_forward( tubeWp ) * 2048;
	}
	
	if ( !isdefined( loc ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "tube", "start", loc, tube );
	
	self SetScriptAimPos( loc );
	self BotStopMoving( true );
	wait 1;
	
	if ( self changeToWeapon( tube ) )
	{
		self thread fire_current_weapon();
		self waittill_any_timeout( 5, "missile_fire", "weapon_change" );
		self notify( "stop_firing_weapon" );
	}
	
	self ClearScriptAimPos();
	self BotStopMoving( false );
}

/*
	Bots thinking of using a noobtube
*/
bot_use_tube_think()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	data = spawnstruct();
	data.dofastcontinue = false;
	
	for ( ;; )
	{
		self bot_use_tube_think_loop( data );
	}
}

/*
	Bots thinking of using claymores
*/
bot_use_equipment_think_loop( data )
{
	if ( data.dofastcontinue )
	{
		data.dofastcontinue = false;
	}
	else
	{
		wait randomintrange( 2, 4 );
		
		chance = self.pers[ "bots" ][ "behavior" ][ "nade" ] / 2;
		
		if ( chance > 20 )
		{
			chance = 20;
		}
		
		if ( randomint( 100 ) > chance )
		{
			return;
		}
	}
	
	nade = undefined;
	
	if ( self getammocount( "claymore_mp" ) )
	{
		nade = "claymore_mp";
	}
	
	if ( self getammocount( "c4_mp" ) )
	{
		nade = "c4_mp";
	}
	
	if ( !isdefined( nade ) )
	{
		return;
	}
	
	if ( self HasThreat() || self HasScriptAimPos() )
	{
		return;
	}
	
	if ( self BotIsFrozen() )
	{
		return;
	}
	
	if ( self IsBotFragging() || self IsBotSmoking() )
	{
		return;
	}
	
	if ( self isDefusing() || self isPlanting() )
	{
		return;
	}
	
	if ( self inLastStand() )
	{
		return;
	}
	
	// never in (or right by) our own spawn, and not in the opening seconds of
	// an S&D round: players plant on approach routes they're holding
	if ( isdefined( self.bot.spawn_origin ) && distancesquared( self.origin, self.bot.spawn_origin ) < 800 * 800 )
	{
		return;
	}
	
	if ( level.gametype == "sd" && isdefined( self.bot.spawn_time ) && gettime() - self.bot.spawn_time < 20000 )
	{
		return;
	}
	
	// C4 goes where fighting has actually happened
	if ( nade == "c4_mp" && !isdefined( bot_pick_fight_spot_near( self.origin, 1200 ) ) )
	{
		return;
	}
	
	curWeap = self getcurrentweapon();
	
	if ( curWeap == "none" || !isWeaponDroppable( curWeap ) )
	{
		if ( !isdefined( self.lastdroppableweapon ) )
		{
			return;
		}
		curWeap = self.lastdroppableweapon;
	}
	
	loc = undefined;
	
	if ( !self nearAnyOfWaypoints( 128, getWaypointsOfType( "claymore" ) ) )
	{
		clayWp = getWaypointForIndex( random( self waypointsNear( getWaypointsOfType( "claymore" ), 1024 ) ) );
		
		if ( !isdefined( clayWp ) || self HasScriptGoal() || self.bot_lock_goal )
		{
			// no "drop it wherever I'm standing": only at a human hold spot
			// (map model) while watching its lane
			if ( !isdefined( self.bot.goal_cell ) || !isdefined( self.bot.goal_view_yaw ) || distancesquared( self.origin, self.bot.goal_cell ) > 200 * 200 )
			{
				return;
			}
			
			myEye = self geteye();
			loc = myEye + anglestoforward( ( 0, self.bot.goal_view_yaw, 0 ) ) * 200;
			
			if ( !bullettracepassed( myEye, loc, false, self ) )
			{
				return;
			}
		}
		else
		{
			self BotNotifyBotEvent( "equ", "go", clayWp, nade );
			
			self SetScriptGoal( clayWp.origin, 16 );
			
			ret = self waittill_any_return( "new_goal", "goal", "bad_path" );
			
			if ( ret != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			if ( ret != "goal" )
			{
				return;
			}
			
			data.dofastcontinue = true;
			return;
		}
	}
	else
	{
		clayWp = getWaypointForIndex( self getNearestWaypointOfWaypoints( getWaypointsOfType( "claymore" ) ) );
		loc = clayWp.origin + bot_wp_forward( clayWp ) * 2048;
	}
	
	if ( !isdefined( loc ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "equ", "start", loc, nade );
	
	self SetScriptAimPos( loc );
	self BotStopMoving( true );
	wait 1;
	
	if ( self changeToWeapon( nade ) )
	{
		if ( nade != "c4_mp" )
		{
			self thread fire_current_weapon();
		}
		else
		{
			self thread fire_c4();
		}
		
		self waittill_any_timeout( 5, "grenade_fire", "weapon_change" );
		self notify( "stop_firing_weapon" );
	}
	
	self thread changeToWeapon( curWeap );
	self ClearScriptAimPos();
	self BotStopMoving( false );
}

/*
	Bots thinking of using claymores
*/
bot_use_equipment_think()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	data = spawnstruct();
	data.dofastcontinue = false;
	
	for ( ;; )
	{
		self bot_use_equipment_think_loop( data );
	}
}

/*
	Bots thinking of using grenades
*/
bot_use_grenade_think_loop( data )
{
	if ( data.dofastcontinue )
	{
		data.dofastcontinue = false;
	}
	else
	{
		wait randomintrange( 4, 7 );
		
		chance = self.pers[ "bots" ][ "behavior" ][ "nade" ] / 2;
		
		if ( chance > 20 )
		{
			chance = 20;
		}
		
		if ( randomint( 100 ) > chance )
		{
			return;
		}
	}
	
	nade = self getValidGrenade();
	
	if ( !isdefined( nade ) )
	{
		return;
	}
	
	if ( self HasThreat() || self HasScriptAimPos() )
	{
		return;
	}
	
	if ( self BotIsFrozen() )
	{
		return;
	}
	
	if ( self IsBotFragging() || self IsBotSmoking() )
	{
		return;
	}
	
	if ( self isDefusing() || self isPlanting() )
	{
		return;
	}
	
	if ( self inLastStand() )
	{
		return;
	}
	
	loc = undefined;
	
	if ( !self nearAnyOfWaypoints( 128, getWaypointsOfType( "grenade" ) ) )
	{
		nadeWp = getWaypointForIndex( random( self waypointsNear( getWaypointsOfType( "grenade" ), 1024 ) ) );
		
		myEye = self geteye();
		
		if ( !isdefined( nadeWp ) || self HasScriptGoal() || self.bot_lock_goal )
		{
			traceForward = bullettrace( myEye, myEye + anglestoforward( self getplayerangles() ) * 900, false, self );
			
			loc = traceForward[ "position" ];
			dist = distancesquared( self.origin, loc );
			
			if ( dist < level.bots_mingrenadedistance || dist > level.bots_maxgrenadedistance )
			{
				return;
			}
			
			if ( !bullettracepassed( self.origin + ( 0, 0, 5 ), self.origin + ( 0, 0, 2048 ), false, self ) )
			{
				return;
			}
			
			if ( !bullettracepassed( loc + ( 0, 0, 5 ), loc + ( 0, 0, 2048 ), false, self ) )
			{
				return;
			}
			
			loc += ( 0, 0, dist / 3000 );
		}
		else
		{
			self BotNotifyBotEvent( "nade", "go", nadeWp, nade );
			
			self SetScriptGoal( nadeWp.origin, 16 );
			
			ret = self waittill_any_return( "new_goal", "goal", "bad_path" );
			
			if ( ret != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			if ( ret != "goal" )
			{
				return;
			}
			
			data.dofastcontinue = true;
			return;
		}
	}
	else
	{
		nadeWp = getWaypointForIndex( self getNearestWaypointOfWaypoints( getWaypointsOfType( "grenade" ) ) );
		loc = nadeWp.origin + bot_wp_forward( nadeWp ) * 2048;
	}
	
	if ( !isdefined( loc ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "nade", "start", loc, nade );
	
	self SetScriptAimPos( loc );
	self BotStopMoving( true );
	wait 1;
	
	time = 0.5;
	
	if ( nade == "frag_grenade_mp" )
	{
		time = 2;
	}
	
	self botThrowGrenade( nade, time );
	
	self ClearScriptAimPos();
	self BotStopMoving( false );
}

/*
	S&D opening nades (NamelessNoobs demos: 69-79% of hand grenades are thrown
	in the first 20s of a round, median ~10s in, frags and flash/stun/smoke about
	50/50): a frag toward the enemy's side of the map, sometimes a tactical after.
	Aimed at the enemy spawn area from the map's spawn points (common knowledge),
	never at actual player positions.
*/
bot_sd_round_nades()
{
	chance = 75;
	persona = self bot_get_persona();
	
	if ( persona == "rusher" )
	{
		chance = 85;
	}
	else if ( persona == "anchor" )
	{
		chance = 50;
	}
	
	if ( randomint( 100 ) >= chance )
	{
		return;
	}
	
	wait randomfloatrange( 4, 16 );
	
	spawnClass = "mp_sd_spawn_defender";
	
	if ( self.team != game[ "attackers" ] )
	{
		spawnClass = "mp_sd_spawn_attacker";
	}
	
	spawns = getentarray( spawnClass, "classname" );
	
	if ( !spawns.size )
	{
		return;
	}
	
	enemySide = ( 0, 0, 0 );
	
	for ( i = 0; i < spawns.size; i++ )
	{
		enemySide += spawns[ i ].origin;
	}
	
	enemySide /= spawns.size;
	
	nades = [];
	
	if ( self getammocount( "frag_grenade_mp" ) )
	{
		nades[ nades.size ] = "frag_grenade_mp";
	}
	
	if ( randomint( 100 ) < 45 )
	{
		tac = self getValidGrenade();
		
		if ( isdefined( tac ) && tac != "frag_grenade_mp" )
		{
			nades[ nades.size ] = tac;
		}
	}
	
	for ( n = 0; n < nades.size; n++ )
	{
		if ( self HasThreat() || self HasScriptAimPos() || self inLastStand() || self IsBotFragging() || self IsBotSmoking() )
		{
			return;
		}
		
		dist = distance( self.origin, enemySide );
		
		if ( dist < 600 )
		{
			return;
		}
		
		// land short of their spawn, along the way: where they'll be walking
		reach = randomfloatrange( 900, 1600 );
		
		if ( reach > dist * 0.8 )
		{
			reach = dist * 0.8;
		}
		
		wp = getNearestWaypoint( self.origin + vectornormalize( enemySide - self.origin ) * reach );
		
		if ( !isdefined( wp ) )
		{
			return;
		}
		
		spot = level.waypoints[ wp ].origin;
		eye = self geteye();
		apex = ( eye + spot ) / 2 + ( 0, 0, distance( eye, spot ) * 0.35 );
		
		if ( !bullettracepassed( eye, apex, false, self ) || !bullettracepassed( apex, spot + ( 0, 0, 40 ), false, self ) )
		{
			self BotTelemetryEvent( "round_nade_noarc" );
			return;
		}
		
		loc = spot + ( 0, 0, distancesquared( self.origin, spot ) / 3000 );
		self BotTelemetryEvent( "round_nade:" + nades[ n ] );
		self SetScriptAimPos( loc );
		wait 0.6;
		
		cook = 0.5;
		
		if ( nades[ n ] == "frag_grenade_mp" )
		{
			cook = randomfloatrange( 0.3, 1.2 );
		}
		
		self botThrowGrenade( nades[ n ], cook );
		self ClearScriptAimPos();
		wait randomfloatrange( 0.8, 2.5 );
	}
}

/*
	Pub habit: lob a frag toward where the fighting is right after spawning.
*/
bot_spawn_nade()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	if ( level.gametype == "sd" )
	{
		self bot_sd_round_nades();
		return;
	}
	
	chance = 12;
	
	if ( self bot_get_persona() == "rusher" )
	{
		chance = 30;
	}
	
	if ( randomint( 100 ) >= chance || !self getammocount( "frag_grenade_mp" ) )
	{
		return;
	}
	
	wait randomfloatrange( 0.4, 1.5 );
	
	if ( self HasThreat() || self HasScriptAimPos() || self inLastStand() || self IsBotFragging() )
	{
		self BotTelemetryEvent( "spawn_nade_busy" );
		return;
	}
	
	spot = self bot_pick_fight_spot( 700, 1800 );
	
	if ( !isdefined( spot ) )
	{
		self BotTelemetryEvent( "spawn_nade_nospot" );
		return;
	}
	
	// the lob needs a clear arc (hand -> apex -> spot), not open sky over both ends
	eye = self geteye();
	apex = ( eye + spot ) / 2 + ( 0, 0, distance( eye, spot ) * 0.35 );
	
	if ( !bullettracepassed( eye, apex, false, self ) || !bullettracepassed( apex, spot + ( 0, 0, 40 ), false, self ) )
	{
		self BotTelemetryEvent( "spawn_nade_noarc" );
		return;
	}
	
	loc = spot + ( 0, 0, distancesquared( self.origin, spot ) / 3000 );
	
	self BotNotifyBotEvent( "nade", "start", loc, "frag_grenade_mp" );
	self BotTelemetryEvent( "spawn_nade" );
	self SetScriptAimPos( loc );
	wait 0.6; // keeps moving: people throw on the run
	self botThrowGrenade( "frag_grenade_mp", randomfloatrange( 0.3, 1.0 ) );
	self ClearScriptAimPos();
}

/*
	Bots thinking of using grenades
*/
bot_use_grenade_think()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	data = spawnstruct();
	data.dofastcontinue = false;
	
	for ( ;; )
	{
		self bot_use_grenade_think_loop( data );
	}
}

/*
	Goes to the target's location if it had one
*/
follow_target_loop()
{
	threat = self getThreat();
	
	if ( !isplayer( threat ) )
	{
		return;
	}
	
	if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "follow" ] * 5 )
	{
		return;
	}
	
	self BotNotifyBotEvent( "follow_threat", "start", threat );
	
	self SetScriptGoal( threat.origin, 64 );
	self thread stop_go_target_on_death( threat );
	
	if ( self waittill_any_return( "new_goal", "goal", "bad_path" ) != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	self BotNotifyBotEvent( "follow_threat", "stop", threat );
}

/*
	Goes to the target's location if it had one
*/
follow_target()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( self HasScriptGoal() || self.bot_lock_goal )
		{
			continue;
		}
		
		if ( !self HasThreat() )
		{
			continue;
		}
		
		self follow_target_loop();
	}
}

/*
	Bot logic for detecting nearby players.
*/
bot_listen_to_steps_loop()
{
	dist = level.bots_listendist;
	
	if ( self hasperk( "specialty_parabolic" ) )
	{
		dist *= 1.4;
	}
	
	dist *= dist;
	
	heard = undefined;
	
	for ( i = level.players.size - 1 ; i >= 0; i-- )
	{
		player = level.players[ i ];
		
		if ( !player IsPlayerModelOK() )
		{
			continue;
		}
		
		if ( player == self )
		{
			continue;
		}
		
		if ( level.teambased && self.team == player.team )
		{
			continue;
		}
		
		if ( player.sessionstate != "playing" )
		{
			continue;
		}
		
		if ( !isalive( player ) )
		{
			continue;
		}
		
		if ( player hasperk( "specialty_quieter" ) )
		{
			continue;
		}
		
		if ( lengthsquared( player getvelocity() ) < 20000 )
		{
			continue;
		}
		
		if ( distancesquared( player.origin, self.origin ) > dist )
		{
			continue;
		}
		
		heard = player;
		break;
	}
	
	if ( !isdefined( heard ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "heard_target", "start", heard );
	
	if ( bullettracepassed( self getEyePos(), heard gettagorigin( "j_spineupper" ), false, heard ) )
	{
		self SetAttacker( heard );
		return;
	}
	
	if ( self HasScriptGoal() || self.bot_lock_goal )
	{
		return;
	}
	
	// Humans hear a vague direction, not GPS coordinates. Search the area.
	heardErr = ( randomintrange( 0 - 250, 250 ), randomintrange( 0 - 250, 250 ), 0 );
	self SetScriptGoal( heard.origin + heardErr, 256 );
	
	if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	self BotNotifyBotEvent( "heard_target", "stop", heard );
}

/*
	Bot logic for detecting nearby players.
*/
bot_listen_to_steps()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( self.pers[ "bots" ][ "skill" ][ "base" ] < 3 )
		{
			continue;
		}
		
		self bot_listen_to_steps_loop();
	}
}

/*
	bots will go to their target's kill location
*/
bot_revenge_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 1 )
	{
		return;
	}
	
	if ( isdefined( self.lastkiller ) && isalive( self.lastkiller ) )
	{
		if ( bullettracepassed( self getEyePos(), self.lastkiller gettagorigin( "j_spineupper" ), false, self.lastkiller ) )
		{
			self SetAttacker( self.lastkiller );
		}
	}
	
	if ( !isdefined( self.killerlocation ) )
	{
		return;
	}
	
	loc = self.killerlocation;
	
	for ( ;; )
	{
		wait( randomintrange( 1, 5 ) );
		
		if ( self HasScriptGoal() || self.bot_lock_goal )
		{
			return;
		}
		
		if ( randomint( 100 ) < 75 )
		{
			return;
		}
		
		self BotNotifyBotEvent( "revenge", "start", loc, self.lastkiller );
		
		self SetScriptGoal( loc, 64 );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		self BotNotifyBotEvent( "revenge", "stop", loc, self.lastkiller );
	}
}

/*
	Reload cancels
*/
doReloadCancel_loop()
{
	ret = self waittill_any_return( "reload", "weapon_change" );
	
	if ( self BotIsFrozen() )
	{
		return;
	}
	
	if ( self isDefusing() || self isPlanting() )
	{
		return;
	}
	
	if ( self inLastStand() )
	{
		return;
	}
	
	curWeap = self getcurrentweapon();
	
	if ( !maps\mp\gametypes\_weapons::issidearm( curWeap ) && !maps\mp\gametypes\_weapons::isprimaryweapon( curWeap ) )
	{
		return;
	}
	
	if ( ret == "reload" )
	{
		// check single reloads
		if ( self getweaponammoclip( curWeap ) < weaponclipsize( curWeap ) )
		{
			return;
		}
	}
	
	// check difficulty
	if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 3 )
	{
		return;
	}
	
	// check if got another weapon
	weaponslist = self getweaponslistprimaries();
	weap = "";
	
	while ( weaponslist.size )
	{
		weapon = weaponslist[ randomint( weaponslist.size ) ];
		weaponslist = array_remove( weaponslist, weapon );
		
		if ( !maps\mp\gametypes\_weapons::issidearm( weapon ) && !maps\mp\gametypes\_weapons::isprimaryweapon( weapon ) )
		{
			continue;
		}
		
		if ( curWeap == weapon || weapon == "none" || weapon == "" )
		{
			continue;
		}
		
		weap = weapon;
		break;
	}
	
	if ( weap == "" )
	{
		return;
	}
	
	// do the cancel
	wait 0.1;
	self thread changeToWeapon( weap );
	wait 0.25;
	self thread changeToWeapon( curWeap );
	wait 2;
}

/*
	Reload cancels
*/
doReloadCancel()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self doReloadCancel_loop();
	}
}

/*
	Bot logic for switching weapons.
*/
bot_weapon_think_loop( data )
{
	ret = self waittill_any_timeout( randomintrange( 2, 4 ), "bot_force_check_switch" );
	
	if ( self BotIsFrozen() )
	{
		return;
	}
	
	if ( self isDefusing() || self isPlanting() || self inLastStand() )
	{
		return;
	}
	
	hasTarget = self HasThreat();
	curWeap = self getcurrentweapon();
	
	if ( hasTarget )
	{
		threat = self getThreat();
		
		if ( !isdefined( threat ) )
		{
			return;
		}
		
		if ( !isdefined( threat.classname ) )
		{
			return;
		}
		
		if ( threat.classname == "script_vehicle" && self getammocount( "rpg_mp" ) )
		{
			if ( curWeap != "rpg_mp" )
			{
				self thread changeToWeapon( "rpg_mp" );
			}
			
			return;
		}
	}
	
	force = ( ret == "bot_force_check_switch" );
	
	if ( data.first )
	{
		data.first = false;
		
		if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "initswitch" ] )
		{
			return;
		}
	}
	else
	{
		if ( curWeap != "none" && self getammocount( curWeap ) )
		{
			if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "switch" ] )
			{
				return;
			}
			
			if ( hasTarget )
			{
				return;
			}
		}
		else
		{
			force = true;
		}
	}
	
	weaponslist = self getweaponslist();
	weap = "";
	
	while ( weaponslist.size )
	{
		weapon = weaponslist[ randomint( weaponslist.size ) ];
		weaponslist = array_remove( weaponslist, weapon );
		
		if ( !self getammocount( weapon ) && !force )
		{
			continue;
		}
		
		if ( maps\mp\gametypes\_weapons::ishackweapon( weapon ) )
		{
			continue;
		}
		
		if ( maps\mp\gametypes\_weapons::isgrenade( weapon ) )
		{
			continue;
		}
		
		if ( curWeap == weapon || weapon == "c4_mp" || weapon == "none" || weapon == "claymore_mp" || weapon == "" )
		{
			continue;
		}
		
		weap = weapon;
		break;
	}
	
	if ( weap == "" )
	{
		return;
	}
	
	self thread changeToWeapon( weap );
}

/*
	Bot logic for switching weapons.
*/
bot_weapon_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	data = spawnstruct();
	data.first = true;
	
	for ( ;; )
	{
		self bot_weapon_think_loop( data );
	}
}

/*
	Bots play mw2
*/
bot_watch_think_mw2_loop()
{
	tube = self getValidTube();
	
	if ( !isdefined( tube ) )
	{
		if ( self getammocount( "rpg_mp" ) )
		{
			tube = "rpg_mp";
		}
		else
		{
			return;
		}
	}
	
	if ( self getcurrentweapon() == tube )
	{
		return;
	}
	
	chance = self.pers[ "bots" ][ "behavior" ][ "nade" ];
	
	if ( randomint( 100 ) > chance )
	{
		return;
	}
	
	self thread changeToWeapon( tube );
}

/*
	Bots play mw2
*/
bot_watch_think_mw2()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	for ( ;; )
	{
		wait randomintrange( 1, 4 );
		
		if ( self BotIsFrozen() )
		{
			continue;
		}
		
		if ( self isDefusing() || self isPlanting() )
		{
			continue;
		}
		
		if ( self inLastStand() )
		{
			continue;
		}
		
		if ( self HasThreat() )
		{
			continue;
		}
		
		self bot_watch_think_mw2_loop();
	}
}

/*
	Bot logic for killstreaks.
*/
bot_killstreak_think_loop()
{
	curWeap = self getcurrentweapon();
	
	if ( curWeap == "radar_mp" || curWeap == "helicopter_mp" || curWeap == "airstrike_mp" )
	{
		if ( isdefined( self.lastdroppableweapon ) )
		{
			self thread changeToWeapon( self.lastdroppableweapon );
		}
		return;
	}
	
	if ( curWeap == "none" || !isWeaponDroppable( curWeap ) )
	{
		if ( isdefined( self.lastdroppableweapon ) )
		{
			curWeap = self.lastdroppableweapon;
		}
		else
		{
			return;
		}
	}
	
	targetPos = undefined;
	
	switch ( self.pers[ "hardPointItem" ] )
	{
		case "radar_mp":
			if ( self.bot_radar && self.pers[ "bots" ][ "skill" ][ "base" ] > 3 )
			{
				return;
			}
			
			break;
			
		case "helicopter_mp":
			chopper = level.chopper;
			
			if ( isdefined( chopper ) && level.teambased && getdvarint( "doubleHeli" ) )
			{
				chopper = level.chopper[ self.team ];
			}
			
			if ( isdefined( chopper ) )
			{
				return;
			}
			
			if ( isdefined( level.mannedchopper ) )
			{
				return;
			}
			
			break;
			
		case "airstrike_mp":
			if ( isdefined( level.airstrikeinprogress ) )
			{
				return;
			}
			
			players = [];
			
			for ( i = level.players.size - 1; i >= 0; i-- )
			{
				player = level.players[ i ];
				
				if ( !player IsPlayerModelOK() )
				{
					continue;
				}
				
				if ( player == self )
				{
					continue;
				}
				
				if ( !isdefined( player.team ) )
				{
					continue;
				}
				
				if ( level.teambased && self.team == player.team )
				{
					continue;
				}
				
				if ( player.sessionstate != "playing" )
				{
					continue;
				}
				
				if ( !isalive( player ) )
				{
					continue;
				}
				
				if ( player hasperk( "specialty_gpsjammer" ) )
				{
					continue;
				}
				
				if ( !bullettracepassed( player.origin, player.origin + ( 0, 0, 512 ), false, player ) && self.pers[ "bots" ][ "skill" ][ "base" ] > 3 )
				{
					continue;
				}
				
				players[ players.size ] = player;
			}
			
			target = random( players );
			
			if ( isdefined( target ) )
			{
				targetPos = target.origin + ( randomintrange( ( 8 - self.pers[ "bots" ][ "skill" ][ "base" ] ) * -75, ( 8 - self.pers[ "bots" ][ "skill" ][ "base" ] ) * 75 ), randomintrange( ( 8 - self.pers[ "bots" ][ "skill" ][ "base" ] ) * -75, ( 8 - self.pers[ "bots" ][ "skill" ][ "base" ] ) * 75 ), 0 );
			}
			else if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 3 )
			{
				targetPos = self.origin + ( randomintrange( -512, 512 ), randomintrange( -512, 512 ), 0 );
			}
			
			break;
			
		default:
			return;
	}
	
	isAirstrikePos = isdefined( targetPos );
	
	if ( self.pers[ "hardPointItem" ] == "airstrike_mp" && !isAirstrikePos )
	{
		return;
	}
	
	self BotNotifyBotEvent( "killstreak", "call", targetPos );
	
	if ( isdefined( self.bot_ks_retry_time ) && gettime() < self.bot_ks_retry_time )
	{
		return;
	}
	
	if ( !self hasweapon( self.pers[ "hardPointItem" ] ) )
	{
		self BotTelemetryEvent( "ks_noweapon:" + self.pers[ "hardPointItem" ] );
		self.bot_ks_retry_time = gettime() + 30000;
		return;
	}
	
	// Keep moving while pulling it out; only stop once it's actually in hand.
	// switchtoweapon can't select hardpoint items for CoD4x bots (it lowers the
	// gun and leaves them empty-handed), and botaction has no actionslot:
	// trigger it the way the stock waiter would, without touching the weapon.
	switched = false;
	
	if ( !switched )
	{
		item = self.pers[ "hardPointItem" ];
		
		if ( self bot_use_hardpoint_direct( item, targetPos ) )
		{
			self BotTelemetryEvent( "ks_direct:" + item );
			return;
		}
		

		self BotTelemetryEvent( "ks_switchfail:" + self.pers[ "hardPointItem" ] );
		self.bot_ks_retry_time = gettime() + 30000;
		return;
	}
	
	self BotTelemetryEvent( "ks_switched:" + self.pers[ "hardPointItem" ] );
	self BotStopMoving( true );
	wait 1;
	
	if ( isAirstrikePos && !isdefined( level.airstrikeinprogress ) )
	{
		self BotFreezeControls( true );
		
		self notify( "confirm_location", targetPos );
		wait 1;
		
		self BotFreezeControls( false );
	}
	
	self BotStopMoving( false );
}

/*
	Never stay empty-handed: if the current weapon is "none" for 1.5s outside
	last stand / planting / defusing, switch back to a weapon with ammo.
*/
bot_weapon_watchdog()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	bad = 0;
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( self getcurrentweapon() != "none" || self inLastStand() || self BotIsFrozen() || self isPlanting() || self isDefusing() )
		{
			bad = 0;
			continue;
		}
		
		bad++;
		
		if ( bad < 3 )
		{
			continue;
		}
		
		bad = 0;
		weaps = self getweaponslist();
		
		for ( i = 0; i < weaps.size; i++ )
		{
			if ( isWeaponDroppable( weaps[ i ] ) && self getammocount( weaps[ i ] ) )
			{
				self BotTelemetryEvent( "weapon_rescue" );
				self BotBuiltinBotWeapon( weaps[ i ] );
				self switchtoweapon( weaps[ i ] );
				break;
			}
		}
	}
}

/*
	S&D: walk to a spot 250-900u from the site and hold an angle there. The
	script goal stays set during the hold so free roaming can't pull us away.
*/
bot_sd_hold_near( site )
{
	spot = undefined;
	
	for ( i = 0; i < 12 && level.waypoints.size; i++ )
	{
		cand = level.waypoints[ randomint( level.waypoints.size ) ].origin;
		d = distancesquared( cand, site );
		
		if ( d > 250 * 250 && d < 900 * 900 )
		{
			spot = cand;
			break;
		}
	}
	
	if ( !isdefined( spot ) )
	{
		return;
	}
	
	self.bot_lock_goal = true;
	self SetScriptGoal( spot, 48 );
	ret = self waittill_any_return( "goal", "bad_path", "new_goal" );
	
	if ( ret == "goal" )
	{
		self maps\mp\bots\_bot_internal::botHoldPosition();
	}
	
	if ( ret != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	self.bot_lock_goal = false;
}

/*
	Uses the held hardpoint without switching weapons: same calls as the stock
	hardpointItemWaiter after its weapon_change. Airstrikes get their location
	confirmed after a human-ish map-pick delay.
*/
bot_use_hardpoint_direct( item, targetPos )
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	if ( item == "airstrike_mp" )
	{
		if ( !isdefined( targetPos ) )
		{
			return false;
		}
		
		self thread bot_confirm_location_after( targetPos, randomfloatrange( 1.2, 2.5 ) );
	}
	
	if ( !self maps\mp\gametypes\_hardpoints::triggerHardpoint( item ) )
	{
		return false;
	}
	
	self notify( "hardpoint_called", item );
	
	if ( isdefined( level.onxpevent ) )
	{
		self thread [[ level.onxpevent ]]( "hardpoint" );
	}
	
	self takeweapon( item );
	self setactionslot( 4, "" );
	self.pers[ "hardPointItem" ] = undefined;
	return true;
}

/*
	Confirms an airstrike location after a delay (the stock selector waits for it).
*/
bot_confirm_location_after( targetPos, delay )
{
	self endon( "death" );
	self endon( "disconnect" );
	
	wait delay;
	self notify( "confirm_location", targetPos );
}

/*
	Bot logic for killstreaks.
*/
bot_killstreak_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	for ( ;; )
	{
		wait randomintrange( 1, 3 );
		
		if ( self BotIsFrozen() )
		{
			continue;
		}
		
		if ( !isdefined( self.pers[ "hardPointItem" ] ) )
		{
			continue;
		}
		
		if ( self HasThreat() )
		{
			continue;
		}
		
		if ( self isDefusing() || self isPlanting() || self inLastStand() )
		{
			continue;
		}
		
		self bot_killstreak_think_loop();
	}
}

/*
	Bot logic for UAV detection here. Checks for UAV and players who are shooting.
*/
bot_uav_think_loop()
{
	dist = self.pers[ "bots" ][ "skill" ][ "help_dist" ];
	dist *= dist * 8;
	
	for ( i = level.players.size - 1; i >= 0; i-- )
	{
		player = level.players[ i ];
		
		if ( !player IsPlayerModelOK() )
		{
			continue;
		}
		
		if ( player == self )
		{
			continue;
		}
		
		if ( !isdefined( player.team ) )
		{
			continue;
		}
		
		if ( player.sessionstate != "playing" )
		{
			continue;
		}
		
		if ( level.teambased && player.team == self.team )
		{
			continue;
		}
		
		if ( !isalive( player ) )
		{
			continue;
		}
		
		distFromPlayer = distancesquared( self.origin, player.origin );
		
		if ( distFromPlayer > dist )
		{
			continue;
		}
		
		if ( ( !issubstr( player getcurrentweapon(), "_silencer_" ) && player.bots_firing ) || ( self.bot_radar && !player hasperk( "specialty_gpsjammer" ) ) )
		{
			self BotNotifyBotEvent( "uav_target", "start", player );
			
			distSq = self.pers[ "bots" ][ "skill" ][ "help_dist" ] * self.pers[ "bots" ][ "skill" ][ "help_dist" ];
			
			if ( distFromPlayer < distSq && bullettracepassed( self getEyePos(), player gettagorigin( "j_spineupper" ), false, player ) )
			{
				self SetAttacker( player );
			}
			
			if ( !self HasScriptGoal() && !self.bot_lock_goal )
			{
			radErr = ( randomintrange( 0 - 200, 200 ), randomintrange( 0 - 200, 200 ), 0 );
			self SetScriptGoal( player.origin + radErr, 256 );
				self thread stop_go_target_on_death( player );
				
				if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
				{
					self ClearScriptGoal();
				}
				
				self BotNotifyBotEvent( "uav_target", "stop", player );
			}
			
			break;
		}
	}
}

/*
	Bot logic for UAV detection here. Checks for UAV and players who are shooting.
*/
bot_uav_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 0.75;
		
		if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 1 )
		{
			continue;
		}
		
		if ( level.hardcoremode && !self.bot_radar )
		{
			continue;
		}
		
		self bot_uav_think_loop();
	}
}

/*
	Bot logic for detecting the chopper as an enemy.
*/
bot_target_vehicle_loop()
{
	chopper = level.chopper;
	
	if ( isdefined( chopper ) && level.teambased && getdvarint( "doubleHeli" ) )
	{
		chopper = level.chopper[ level.otherteam[ self.team ] ];
	}
	
	if ( !isdefined( chopper ) )
	{
		return;
	}
	
	if ( !isdefined( level.bot_chopper ) || !level.bot_chopper ) // must be crashing or leaving
	{
		return;
	}
	
	if ( isdefined( chopper.owner ) && chopper.owner == self )
	{
		return;
	}
	
	if ( chopper.team == self.team && level.teambased )
	{
		return;
	}
	
	if ( !bullettracepassed( self getEyePos(), chopper.origin + ( 0, 0, -5 ), false, chopper ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "attack_vehicle", "start", chopper );
	
	self SetScriptEnemy( chopper, ( 0, 0, -5 ) );
	self bot_attack_vehicle( chopper );
	self ClearScriptEnemy();
	self notify( "bot_force_check_switch" );
	
	self BotNotifyBotEvent( "attack_vehicle", "stop", chopper );
}

/*
	Bot logic for detecting the chopper as an enemy.
*/
bot_target_vehicle()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait( randomintrange( 2, 4 ) );
		
		if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 1 )
		{
			continue;
		}
		
		if ( self HasScriptEnemy() )
		{
			continue;
		}
		
		if ( !self getammocount( "rpg_mp" ) && self BotGetRandom() < 90 )
		{
			continue;
		}
		
		self bot_target_vehicle_loop();
	}
}

/*
	Bot logic for how long to keep targeting chopper.
*/
bot_attack_vehicle( chopper )
{
	chopper endon( "death" );
	chopper endon( "crashing" );
	chopper endon( "leaving" );
	
	wait_time = randomintrange( 7, 10 );
	
	for ( i = 0; i < wait_time; i++ )
	{
		self notify( "bot_force_check_switch" );
		wait( 1 );
		
		if ( !isdefined( chopper ) )
		{
			return;
		}
	}
}

/*
	Bot logic for targeting equipment.
*/
bot_equipment_kill_think_loop()
{
	grenades = getentarray( "grenade", "classname" );
	myEye = self getEyePos();
	myAngles = self getplayerangles();
	target = undefined;
	hasDetectExp = self hasperk( "specialty_detectexplosive" );
	
	for ( i = grenades.size - 1; i >= 0; i-- )
	{
		item = grenades[ i ];
		
		if ( !isdefined( item ) )
		{
			continue;
		}
		
		if ( !isdefined( item.name ) )
		{
			continue;
		}
		
		if ( isdefined( item.owner ) && ( ( level.teambased && item.owner.team == self.team ) || item.owner == self ) )
		{
			continue;
		}
		
		if ( item.name != "c4_mp" && item.name != "claymore_mp" )
		{
			continue;
		}
		
		if ( !hasDetectExp && !bullettracepassed( myEye, item.origin + ( 0, 0, 0 ), false, item ) )
		{
			continue;
		}
		
		if ( getConeDot( item.origin, self.origin, myAngles ) < 0.6 )
		{
			continue;
		}
		
		if ( distancesquared( item.origin, self.origin ) < 512 * 512 )
		{
			target = item;
			break;
		}
	}
	
	if ( isdefined( target ) )
	{
		self BotNotifyBotEvent( "attack_equ", "start", target );
		
		self SetScriptEnemy( target, ( 0, 0, 0 ) );
		self bot_equipment_attack( target );
		self ClearScriptEnemy();
		
		self BotNotifyBotEvent( "attack_equ", "stop", target );
	}
}

/*
	Bot logic for targeting equipment.
*/
bot_equipment_kill_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait( randomintrange( 1, 3 ) );
		
		if ( self HasScriptEnemy() )
		{
			continue;
		}
		
		if ( self.pers[ "bots" ][ "skill" ][ "base" ] <= 1 )
		{
			continue;
		}
		
		self bot_equipment_kill_think_loop();
	}
}

/*
	How long to keep targeting the equipment.
*/
bot_equipment_attack( equ )
{
	equ endon( "death" );
	
	wait_time = randomintrange( 7, 10 );
	
	for ( i = 0; i < wait_time; i++ )
	{
		wait( 1 );
		
		if ( !isdefined( equ ) )
		{
			return;
		}
	}
}

/*
	Bots do random stance
*/
BotRandomStance()
{
	if ( randomint( 100 ) < 80 )
	{
		self BotSetStance( "prone" );
	}
	else if ( randomint( 100 ) < 60 )
	{
		self BotSetStance( "crouch" );
	}
	else
	{
		self BotSetStance( "stand" );
	}
}

/*
	Bots will use a random equipment
*/
BotUseRandomEquipment()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	equ = undefined;
	
	if ( self getammocount( "claymore_mp" ) )
	{
		equ = "claymore_mp";
	}
	
	if ( self getammocount( "c4_mp" ) )
	{
		equ = "c4_mp";
	}
	
	if ( !isdefined( equ ) )
	{
		return;
	}
	
	curWeap = self getcurrentweapon();
	
	if ( self changeToWeapon( equ ) )
	{
		if ( equ != "c4_mp" )
		{
			self thread fire_current_weapon();
		}
		else
		{
			self thread fire_c4();
		}
		
		self waittill_any_timeout( 5, "grenade_fire", "weapon_change" );
		self notify( "stop_firing_weapon" );
	}
	
	self thread changeToWeapon( curWeap );
}

/*
	Bots will look at a random thing
*/
BotLookAtRandomThing( obj_target )
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( self HasScriptAimPos() )
	{
		return;
	}
	
	rand = randomint( 100 );
	
	nearestEnemy = undefined;
	
	for ( i = 0; i < level.players.size; i++ )
	{
		player = level.players[ i ];
		
		if ( !isdefined( player ) || !isdefined( player.team ) )
		{
			continue;
		}
		
		if ( !isalive( player ) )
		{
			continue;
		}
		
		if ( level.teambased && self.team == player.team )
		{
			continue;
		}
		
		if ( !isdefined( nearestEnemy ) || distancesquared( self.origin, player.origin ) < distancesquared( self.origin, nearestEnemy.origin ) )
		{
			nearestEnemy = player;
		}
	}
	
	origin = ( 0, 0, self getEyeHeight() );
	
	if ( isdefined( nearestEnemy ) && distancesquared( self.origin, nearestEnemy.origin ) < 1024 * 1024 && rand < 40 )
	{
		origin += ( nearestEnemy.origin[ 0 ], nearestEnemy.origin[ 1 ], self.origin[ 2 ] );
	}
	else if ( isdefined( obj_target ) && rand < 50 )
	{
		origin += ( obj_target.origin[ 0 ], obj_target.origin[ 1 ], self.origin[ 2 ] );
	}
	else if ( rand < 85 )
	{
		origin += self.origin + anglestoforward( ( 0, self.angles[ 1 ] - 180, 0 ) ) * 1024;
	}
	else
	{
		origin += self.origin + anglestoforward( ( 0, randomint( 360 ), 0 ) ) * 1024;
	}
	
	self SetScriptAimPos( origin );
	wait 2;
	self ClearScriptAimPos();
}

/*
	Bots will do stuff while waiting for objective
*/
bot_do_random_action_for_objective( obj_target )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_do_random_action_for_objective" );
	self endon( "bot_do_random_action_for_objective" );
	
	if ( !isdefined( self.bot_random_obj_action ) )
	{
		self.bot_random_obj_action = true;
		
		if ( randomint( 100 ) < 80 )
		{
			self thread BotUseRandomEquipment();
		}
		
		if ( randomint( 100 ) < 75 )
		{
			self thread BotLookAtRandomThing( obj_target );
		}
	}
	else
	{
		if ( self getstance() != "prone" && randomint( 100 ) < 15 )
		{
			self BotSetStance( "prone" );
		}
		else if ( randomint( 100 ) < 5 )
		{
			self thread BotLookAtRandomThing( obj_target );
		}
	}
	
	wait 2;
	self.bot_random_obj_action = undefined;
}

/*
	Bots hang around the enemy's flag to spawn kill em
*/
bot_dom_spawn_kill_think_loop()
{
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	myFlagCount = maps\mp\gametypes\dom::getteamflagcount( myTeam );
	
	if ( myFlagCount == level.flags.size )
	{
		return;
	}
	
	otherFlagCount = maps\mp\gametypes\dom::getteamflagcount( otherTeam );
	
	if ( myFlagCount <= otherFlagCount || otherFlagCount != 1 )
	{
		return;
	}
	
	flag = undefined;
	
	for ( i = 0; i < level.flags.size; i++ )
	{
		if ( level.flags[ i ] maps\mp\gametypes\dom::getflagteam() == myTeam )
		{
			continue;
		}
		
		flag = level.flags[ i ];
	}
	
	if ( !isdefined( flag ) )
	{
		return;
	}
	
	if ( distancesquared( self.origin, flag.origin ) < 2048 * 2048 )
	{
		return;
	}
	
	self BotNotifyBotEvent( "dom", "start", "spawnkill", flag );
	
	self SetScriptGoal( flag.origin, 1024 );
	
	self thread bot_dom_watch_flags( myFlagCount, myTeam );
	
	if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	self BotNotifyBotEvent( "dom", "stop", "spawnkill", flag );
}

/*
	Bots hang around the enemy's flag to spawn kill em
*/
bot_dom_spawn_kill_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( level.gametype != "dom" )
	{
		return;
	}
	
	for ( ;; )
	{
		wait( randomintrange( 10, 20 ) );
		
		if ( randomint( 100 ) < 20 )
		{
			continue;
		}
		
		if ( self HasScriptGoal() || self.bot_lock_goal )
		{
			continue;
		}
		
		self bot_dom_spawn_kill_think_loop();
	}
}

/*
	Calls 'bad_path' when the flag count changes
*/
bot_dom_watch_flags( count, myTeam )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( maps\mp\gametypes\dom::getteamflagcount( myTeam ) != count )
		{
			break;
		}
	}
	
	self notify( "bad_path" );
}

/*
	Bots watches their own flags and protects them when they are under capture
*/
bot_dom_def_think_loop()
{
	myTeam = self.pers[ "team" ];
	flag = undefined;
	
	for ( i = 0; i < level.flags.size; i++ )
	{
		if ( level.flags[ i ] maps\mp\gametypes\dom::getflagteam() != myTeam )
		{
			continue;
		}
		
		if ( !level.flags[ i ].useobj.objpoints[ myTeam ].isflashing )
		{
			continue;
		}
		
		if ( !isdefined( flag ) || distancesquared( self.origin, level.flags[ i ].origin ) < distancesquared( self.origin, flag.origin ) )
		{
			flag = level.flags[ i ];
		}
	}
	
	if ( !isdefined( flag ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "dom", "start", "defend", flag );
	
	self SetScriptGoal( flag.origin, 128 );
	
	self thread bot_dom_watch_for_flashing( flag, myTeam );
	self thread bots_watch_touch_obj( flag );
	
	if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	self BotNotifyBotEvent( "dom", "stop", "defend", flag );
}

/*
	Bots watches their own flags and protects them when they are under capture
*/
bot_dom_def_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( level.gametype != "dom" )
	{
		return;
	}
	
	for ( ;; )
	{
		wait( randomintrange( 1, 3 ) );
		
		if ( randomint( 100 ) < 35 )
		{
			continue;
		}
		
		if ( self HasScriptGoal() || self.bot_lock_goal )
		{
			continue;
		}
		
		self bot_dom_def_think_loop();
	}
}

/*
	Watches while the flag is under capture
*/
bot_dom_watch_for_flashing( flag, myTeam )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !isdefined( flag ) )
		{
			break;
		}
		
		if ( flag maps\mp\gametypes\dom::getflagteam() != myTeam || !flag.useobj.objpoints[ myTeam ].isflashing )
		{
			break;
		}
	}
	
	self notify( "bad_path" );
}

/*
	Bots capture dom flags
*/
bot_dom_cap_think_loop()
{
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	
	myFlagCount = maps\mp\gametypes\dom::getteamflagcount( myTeam );
	
	if ( myFlagCount == level.flags.size )
	{
		return;
	}
	
	otherFlagCount = maps\mp\gametypes\dom::getteamflagcount( otherTeam );
	
	if ( game[ "teamScores" ][ myTeam ] >= game[ "teamScores" ][ otherTeam ] )
	{
		if ( myFlagCount < otherFlagCount )
		{
			if ( randomint( 100 ) < 15 )
			{
				return;
			}
		}
		else if ( myFlagCount == otherFlagCount )
		{
			if ( randomint( 100 ) < 35 )
			{
				return;
			}
		}
		else if ( myFlagCount > otherFlagCount )
		{
			if ( randomint( 100 ) < 95 )
			{
				return;
			}
		}
	}
	
	flag = undefined;
	flags = [];
	
	for ( i = 0; i < level.flags.size; i++ )
	{
		if ( level.flags[ i ] maps\mp\gametypes\dom::getflagteam() == myTeam )
		{
			continue;
		}
		
		if ( isdefined( level.flags[ i ].bots ) && level.flags[ i ].bots >= 3 )
		{
			continue;
		}
		
		flags[ flags.size ] = level.flags[ i ];
	}
	
	if ( randomint( 100 ) > 30 )
	{
		for ( i = 0; i < flags.size; i++ )
		{
			if ( !isdefined( flag ) || distancesquared( self.origin, level.flags[ i ].origin ) < distancesquared( self.origin, flag.origin ) )
			{
				flag = level.flags[ i ];
			}
		}
	}
	else if ( flags.size )
	{
		flag = random( flags );
	}
	
	if ( !isdefined( flag ) )
	{
		return;
	}
	
	self BotNotifyBotEvent( "dom", "go", "cap", flag );
	
	self.bot_lock_goal = true;
	self thread bot_inc_bots( flag );
	self SetScriptGoal( flag.origin, 64 );
	
	self thread bot_dom_go_cap_flag( flag, myTeam );
	
	event = self waittill_any_return( "goal", "bad_path", "new_goal" );
	
	if ( event != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	if ( event != "goal" )
	{
		self.bot_lock_goal = false;
		return;
	}
	
	self BotNotifyBotEvent( "dom", "start", "cap", flag );
	
	self SetScriptGoal( self.origin, 64 );
	
	while ( flag maps\mp\gametypes\dom::getflagteam() != myTeam && self istouching( flag ) )
	{
		cur = flag.useobj.curprogress;
		wait 0.5;
		
		if ( flag.useobj.curprogress == cur )
		{
			break; // some enemy is near us, kill him
		}
		
		self thread bot_do_random_action_for_objective( flag );
	}
	
	self BotNotifyBotEvent( "dom", "stop", "cap", flag );
	
	self ClearScriptGoal();
	
	self.bot_lock_goal = false;
}

/*
	Bots capture dom flags
*/
bot_dom_cap_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( level.gametype != "dom" )
	{
		return;
	}
	
	for ( ;; )
	{
		wait( randomintrange( 3, 12 ) );
		
		if ( self.bot_lock_goal )
		{
			continue;
		}
		
		if ( !isdefined( level.flags ) || level.flags.size == 0 )
		{
			continue;
		}
		
		self bot_dom_cap_think_loop();
	}
}

/*
	Bot goes to the flag, watching while they don't have the flag
*/
bot_dom_go_cap_flag( flag, myTeam )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait randomintrange( 2, 4 );
		
		if ( !isdefined( flag ) )
		{
			break;
		}
		
		if ( flag maps\mp\gametypes\dom::getflagteam() == myTeam )
		{
			break;
		}
		
		if ( self istouching( flag ) )
		{
			break;
		}
	}
	
	if ( flag maps\mp\gametypes\dom::getflagteam() == myTeam )
	{
		self notify( "bad_path" );
	}
	else
	{
		self notify( "goal" );
	}
}

/*
	Bots play headquarters
*/
bot_hq_loop()
{
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	
	if ( !isdefined( level.radio ) )
	{
		return;
	}
	
	radio = level.radio;
	if ( !isdefined( radio.gameobject ) || !isdefined( radio.origin ) )
	{
		return;
	}
	gameobj = radio.gameobject;
	origin = ( radio.origin[ 0 ], radio.origin[ 1 ], radio.origin[ 2 ] + 5 );
	
	// if neut or enemy
	if ( gameobj.ownerteam != myTeam )
	{
		if ( gameobj.interactteam == "none" ) // wait for it to become active
		{
			if ( self HasScriptGoal() )
			{
				return;
			}
			
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self SetScriptGoal( origin, 256 );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			return;
		}
		
		// capture it
		
		self BotNotifyBotEvent( "hq", "go", "cap" );
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 64 );
		self thread bot_hq_go_cap( gameobj, radio );
		
		event = self waittill_any_return( "goal", "bad_path", "new_goal" );
		
		if ( event != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		if ( event != "goal" )
		{
			self.bot_lock_goal = false;
			return;
		}
		
		if ( !self istouching( gameobj.trigger ) || level.radio != radio )
		{
			self.bot_lock_goal = false;
			return;
		}
		
		self BotNotifyBotEvent( "hq", "start", "cap" );
		
		self SetScriptGoal( self.origin, 64 );
		
		while ( self istouching( gameobj.trigger ) && gameobj.ownerteam != myTeam && level.radio == radio )
		{
			cur = gameobj.curprogress;
			wait 0.5;
			
			if ( cur == gameobj.curprogress )
			{
				break; // no prog made, enemy must be capping
			}
			
			self thread bot_do_random_action_for_objective( gameobj.trigger );
		}
		
		self ClearScriptGoal();
		self.bot_lock_goal = false;
		
		self BotNotifyBotEvent( "hq", "stop", "cap" );
	}
	else // we own it
	{
		if ( gameobj.objpoints[ myTeam ].isflashing ) // underattack
		{
			self BotNotifyBotEvent( "hq", "start", "defend" );
			
			self.bot_lock_goal = true;
			self SetScriptGoal( origin, 64 );
			self thread bot_hq_watch_flashing( gameobj, radio );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			self.bot_lock_goal = false;
			
			self BotNotifyBotEvent( "hq", "stop", "defend" );
			return;
		}
		
		if ( self HasScriptGoal() )
		{
			return;
		}
		
		if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
		{
			return;
		}
		
		self SetScriptGoal( origin, 256 );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
	}
}

/*
	Bots play headquarters
*/
bot_hq()
{
	self endon( "death" );
	self endon( "disconnect" );
	
	if ( level.gametype != "koth" )
	{
		return;
	}
	
	for ( ;; )
	{
		wait( randomintrange( 3, 5 ) );
		
		if ( self.bot_lock_goal )
		{
			continue;
		}
		
		if ( !isdefined( level.radio ) )
		{
			continue;
		}
		
		if ( !isdefined( level.radio.gameobject ) )
		{
			continue;
		}
		
		self bot_hq_loop();
	}
}

/*
	Waits until not touching the trigger and it is the current radio.
*/
bot_hq_go_cap( obj, radio )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	for ( ;; )
	{
		wait randomintrange( 2, 4 );
		
		if ( !isdefined( obj ) )
		{
			break;
		}
		
		if ( self istouching( obj.trigger ) )
		{
			break;
		}
		
		if ( level.radio != radio )
		{
			break;
		}
	}
	
	if ( level.radio != radio )
	{
		self notify( "bad_path" );
	}
	else
	{
		self notify( "goal" );
	}
}

/*
	Waits while the radio is under attack.
*/
bot_hq_watch_flashing( obj, radio )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "goal" );
	self endon( "bad_path" );
	self endon( "new_goal" );
	
	myteam = self.team;
	
	for ( ;; )
	{
		wait 0.5;
		
		if ( !isdefined( obj ) )
		{
			break;
		}
		
		if ( !obj.objpoints[ myteam ].isflashing )
		{
			break;
		}
		
		if ( level.radio != radio )
		{
			break;
		}
	}
	
	self notify( "bad_path" );
}

/*
	Bots play sab
*/
bot_sab_loop()
{
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	
	bomb = level.sabbomb;
	bombteam = bomb.ownerteam;
	carrier = bomb.carrier;
	timeleft = maps\mp\gametypes\_globallogic::gettimeremaining() / 1000;
	
	// the bomb is ours, we are on the offence
	if ( bombteam == myTeam )
	{
		site = level.bombzones[ otherTeam ];
		origin = ( site.curorigin[ 0 ] + 50, site.curorigin[ 1 ] + 50, site.curorigin[ 2 ] + 5 );
		
		// protect our planted bomb
		if ( level.bombplanted )
		{
			// kill defuser
			if ( site isInUse() ) // somebody is defusing our bomb we planted
			{
				self BotNotifyBotEvent( "sab", "start", "defuser" );
				
				self.bot_lock_goal = true;
				self SetScriptGoal( origin, 64 );
				
				self thread bot_defend_site( site );
				
				if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
				{
					self ClearScriptGoal();
				}
				
				self.bot_lock_goal = false;
				
				self BotNotifyBotEvent( "sab", "stop", "defuser" );
				return;
			}
			
			// else hang around the site
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self.bot_lock_goal = true;
			self SetScriptGoal( origin, 256 );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			self.bot_lock_goal = false;
			return;
		}
		
		// we are not the carrier
		if ( !self isBombCarrier() )
		{
			// lets escort the bomb carrier
			if ( self HasScriptGoal() )
			{
				return;
			}
			
			if ( !isdefined( carrier ) || !isalive( carrier ) )
			{
				origin = bomb.origin;
			}
			else
			{
				origin = carrier.origin;
			}
			
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self SetScriptGoal( origin, 256 );
			self thread bot_escort_obj( bomb, carrier );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			return;
		}
		
		// we are the carrier of the bomb, lets check if we need to plant
		timepassed = maps\mp\gametypes\_globallogic::gettimepassed() / 1000;
		
		if ( timepassed < 120 && timeleft >= 90 && randomint( 100 ) < 98 )
		{
			return;
		}
		
		self BotNotifyBotEvent( "sab", "go", "plant" );
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 1 );
		
		self thread bot_go_plant( site );
		event = self waittill_any_return( "goal", "bad_path", "new_goal" );
		
		if ( event != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		urgent = timeleft < 20;
		
		if ( event != "goal" || level.bombplanted || !self istouching( site.trigger ) || site isInUse() || self inLastStand() || ( self HasThreat() && !urgent ) )
		{
			self.bot_lock_goal = false;
			return;
		}
		
		self BotNotifyBotEvent( "sab", "start", "plant" );
		
		self BotRandomStance();
		self SetScriptGoal( self.origin, 64 );
		self bot_wait_stop_move();
		
		waitTime = ( site.usetime / 1000 ) + 2.5;
		self thread BotPressUse( waitTime );
		wait waitTime;
		
		self ClearScriptGoal();
		self.bot_lock_goal = false;
		
		self BotNotifyBotEvent( "sab", "stop", "plant" );
	}
	else if ( bombteam == otherTeam ) // the bomb is theirs, we are on the defense
	{
		site = level.bombzones[ myTeam ];
		
		if ( !isdefined( site.bots ) )
		{
			site.bots = 0;
		}
		
		// protect our site from planters
		if ( !level.bombplanted )
		{
			// kill bomb carrier
			if ( site.bots > 2 || randomint( 100 ) < 45 )
			{
				if ( self HasScriptGoal() )
				{
					return;
				}
				
				if ( !isdefined( carrier ) || !isalive( carrier ) )
				{
					origin = bomb.origin;
				}
				else
				{
					if ( carrier hasperk( "specialty_gpsjammer" ) )
					{
						return;
					}
					
					origin = carrier.origin;
				}
				
				self SetScriptGoal( origin, 64 );
				self thread bot_escort_obj( bomb, carrier );
				
				if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
				{
					self ClearScriptGoal();
				}
				
				return;
			}
			
			// protect bomb site
			origin = ( site.curorigin[ 0 ] + 50, site.curorigin[ 1 ] + 50, site.curorigin[ 2 ] + 5 );
			
			self thread bot_inc_bots( site );
			
			if ( site isInUse() ) // somebody is planting
			{
				self BotNotifyBotEvent( "sab", "start", "planter" );
				
				self.bot_lock_goal = true;
				self SetScriptGoal( origin, 64 );
				self thread bot_inc_bots( site );
				
				self thread bot_defend_site( site );
				
				if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
				{
					self ClearScriptGoal();
				}
				
				self.bot_lock_goal = false;
				
				self BotNotifyBotEvent( "sab", "stop", "planter" );
				return;
			}
			
			// else hang around the site
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				wait 4;
				self notify( "bot_inc_bots" );
				site.bots--;
				return;
			}
			
			self.bot_lock_goal = true;
			self SetScriptGoal( origin, 256 );
			self thread bot_inc_bots( site );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			self.bot_lock_goal = false;
			return;
		}
		
		// bomb is planted we need to defuse
		origin = ( site.curorigin[ 0 ] + 50, site.curorigin[ 1 ] + 50, site.curorigin[ 2 ] + 5 );
		
		// someone else is defusing, lets just hang around
		if ( site.bots > 1 )
		{
			if ( self HasScriptGoal() )
			{
				return;
			}
			
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self SetScriptGoal( origin, 256 );
			self thread bot_go_defuse( site );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			return;
		}
		
		// lets go defuse
		self BotNotifyBotEvent( "sab", "go", "defuse" );
		
		self.bot_lock_goal = true;
		
		self SetScriptGoal( origin, 1 );
		self thread bot_inc_bots( site );
		self thread bot_go_defuse( site );
		
		event = self waittill_any_return( "goal", "bad_path", "new_goal" );
		
		if ( event != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		if ( event != "goal" || !level.bombplanted || site isInUse() || !self istouching( site.trigger ) || self inLastStand() || self HasThreat() )
		{
			self.bot_lock_goal = false;
			return;
		}
		
		self BotNotifyBotEvent( "sab", "start", "defuse" );
		
		self BotRandomStance();
		self SetScriptGoal( self.origin, 64 );
		self bot_wait_stop_move();
		
		waitTime = ( site.usetime / 1000 ) + 2.5;
		self thread BotPressUse( waitTime );
		wait waitTime;
		
		self ClearScriptGoal();
		self.bot_lock_goal = false;
		
		self BotNotifyBotEvent( "sab", "stop", "defuse" );
	}
	else // we need to go get the bomb!
	{
		origin = ( bomb.curorigin[ 0 ], bomb.curorigin[ 1 ], bomb.curorigin[ 2 ] + 5 );
		
		self BotNotifyBotEvent( "sab", "start", "bomb" );
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 64 );
		
		self thread bot_get_obj( bomb );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		self.bot_lock_goal = false;
		
		self BotNotifyBotEvent( "sab", "stop", "bomb" );
		return;
	}
}

/*
	Bots play sab
*/
bot_sab()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	if ( level.gametype != "sab" )
	{
		return;
	}
	
	for ( ;; )
	{
		wait( randomintrange( 3, 5 ) );
		
		if ( self.bot_lock_goal )
		{
			continue;
		}
		
		if ( !isdefined( level.sabbomb ) )
		{
			continue;
		}
		
		if ( !isdefined( level.bombzones ) || !level.bombzones.size )
		{
			continue;
		}
		
		if ( self isPlanting() || self isDefusing() )
		{
			continue;
		}
		
		self bot_sab_loop();
	}
}

/*
	Bots play sd defenders
*/
bot_sd_defenders_loop( data )
{
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	
	// bomb not planted, lets protect our sites
	if ( !level.bombplanted )
	{
		timeleft = maps\mp\gametypes\_globallogic::gettimeremaining() / 1000;
		
		if ( timeleft >= 90 )
		{
			return;
		}
		
		// check for a bomb carrier, and camp the bomb
		if ( !level.multibomb && isdefined( level.sdbomb ) )
		{
			bomb = level.sdbomb;
			carrier = level.sdbomb.carrier;
			
			if ( !isdefined( carrier ) )
			{
				origin = ( bomb.curorigin[ 0 ], bomb.curorigin[ 1 ], bomb.curorigin[ 2 ] + 5 );
				
				// hang around the bomb
				if ( self HasScriptGoal() )
				{
					return;
				}
				
				if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
				{
					return;
				}
				
				self SetScriptGoal( origin, 256 );
				
				self thread bot_get_obj( bomb );
				
				if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
				{
					self ClearScriptGoal();
				}
				
				return;
			}
		}
		
		// pick a site to protect
		if ( !isdefined( level.bombzones ) || !level.bombzones.size )
		{
			return;
		}
		
		sites = [];
		
		for ( i = 0; i < level.bombzones.size; i++ )
		{
			sites[ sites.size ] = level.bombzones[ i ];
		}
		
		if ( !sites.size )
		{
			return;
		}
		
		if ( data.rand > 50 )
		{
			site = self bot_array_nearest_curorigin( sites );
		}
		else
		{
			site = random( sites );
		}
		
		if ( !isdefined( site ) )
		{
			return;
		}
		
		origin = ( site.curorigin[ 0 ] + 50, site.curorigin[ 1 ] + 50, site.curorigin[ 2 ] + 5 );
		
		if ( site isInUse() ) // somebody is planting
		{
			self BotNotifyBotEvent( "sd", "start", "planter", site );
			
			self.bot_lock_goal = true;
			self SetScriptGoal( origin, 64 );
			
			self thread bot_defend_site( site );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			self.bot_lock_goal = false;
			
			self BotNotifyBotEvent( "sd", "stop", "planter", site );
			return;
		}
		
		// else hold an angle covering the site, like real S&D players do
		// (previously they free-roamed to random waypoints anywhere on the map)
		if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
		{
			if ( !self HasScriptGoal() && randomint( 100 ) < 80 )
			{
				self bot_sd_hold_near( origin );
			}
			
			return;
		}
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 256 );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		self.bot_lock_goal = false;
		return;
	}
	
	// bomb is planted, we need to defuse
	if ( !isdefined( level.defuseobject ) )
	{
		return;
	}
	
	defuse = level.defuseobject;
	
	if ( !isdefined( defuse.bots ) )
	{
		defuse.bots = 0;
	}
	
	origin = ( defuse.curorigin[ 0 ], defuse.curorigin[ 1 ], defuse.curorigin[ 2 ] + 5 );
	
	// someone is going to go defuse ,lets just hang around
	if ( defuse.bots > 1 )
	{
		if ( self HasScriptGoal() )
		{
			return;
		}
		
		if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
		{
			return;
		}
		
		self SetScriptGoal( origin, 256 );
		self thread bot_go_defuse( defuse );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		return;
	}
	
	// lets defuse
	self BotNotifyBotEvent( "sd", "go", "defuse" );
	
	self.bot_lock_goal = true;
	self SetScriptGoal( origin, 1 );
	self thread bot_inc_bots( defuse );
	self thread bot_go_defuse( defuse );
	
	event = self waittill_any_return( "goal", "bad_path", "new_goal" );
	
	if ( event != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	if ( event != "goal" || !level.bombplanted || defuse isInUse() || !self istouching( defuse.trigger ) || self inLastStand() || self HasThreat() )
	{
		self.bot_lock_goal = false;
		return;
	}
	
	self BotNotifyBotEvent( "sd", "start", "defuse" );
	
	self BotRandomStance();
	self SetScriptGoal( self.origin, 64 );
	self bot_wait_stop_move();
	
	waitTime = ( defuse.usetime / 1000 ) + 2.5;
	self thread BotPressUse( waitTime );
	wait waitTime;
	
	self ClearScriptGoal();
	self.bot_lock_goal = false;
	
	self BotNotifyBotEvent( "sd", "stop", "defuse" );
}

/*
	Bots play sd defenders
*/
bot_sd_defenders()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	if ( level.gametype != "sd" )
	{
		return;
	}
	
	if ( self.team == game[ "attackers" ] )
	{
		return;
	}
	
	data = spawnstruct();
	data.rand = self BotGetRandom();
	
	for ( ;; )
	{
		wait( randomintrange( 3, 5 ) );
		
		if ( self.bot_lock_goal )
		{
			continue;
		}
		
		if ( self isPlanting() || self isDefusing() )
		{
			continue;
		}
		
		self bot_sd_defenders_loop( data );
	}
}

/*
	Bots play sd attackers
*/
bot_sd_attackers_loop( data )
{
	if ( data.first )
	{
		data.first = false;
	}
	else
	{
		wait( randomintrange( 3, 5 ) );
	}
	
	if ( self.bot_lock_goal )
	{
		return;
	}
	
	myTeam = self.pers[ "team" ];
	otherTeam = getotherteam( myTeam );
	
	// bomb planted
	if ( level.bombplanted )
	{
		if ( !isdefined( level.defuseobject ) )
		{
			return;
		}
		
		site = level.defuseobject;
		
		origin = ( site.curorigin[ 0 ], site.curorigin[ 1 ], site.curorigin[ 2 ] + 5 );
		
		if ( site isInUse() ) // somebody is defusing
		{
			self BotNotifyBotEvent( "sd", "start", "defuser" );
			
			self.bot_lock_goal = true;
			
			self SetScriptGoal( origin, 64 );
			
			self thread bot_defend_site( site );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			self.bot_lock_goal = false;
			
			self BotNotifyBotEvent( "sd", "stop", "defuser" );
			return;
		}
		
		// else hold an angle covering the site, like real S&D players do
		// (previously they free-roamed to random waypoints anywhere on the map)
		if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
		{
			if ( !self HasScriptGoal() && randomint( 100 ) < 80 )
			{
				self bot_sd_hold_near( origin );
			}
			
			return;
		}
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 256 );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		self.bot_lock_goal = false;
		return;
	}
	
	timeleft = maps\mp\gametypes\_globallogic::gettimeremaining() / 1000;
	timepassed = maps\mp\gametypes\_globallogic::gettimepassed() / 1000;
	
	// dont have a bomb
	if ( !self isBombCarrier() && !level.multibomb )
	{
		if ( !isdefined( level.sdbomb ) )
		{
			return;
		}
		
		bomb = level.sdbomb;
		carrier = level.sdbomb.carrier;
		
		// bomb is picked up
		if ( isdefined( carrier ) && isalive( carrier ) )
		{
			// escort the bomb carrier
			if ( self HasScriptGoal() )
			{
				return;
			}
			
			origin = carrier.origin;
			
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self SetScriptGoal( origin, 256 );
			self thread bot_escort_obj( bomb, carrier );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			return;
		}
		
		if ( !isdefined( bomb.bots ) )
		{
			bomb.bots = 0;
		}
		
		origin = ( bomb.curorigin[ 0 ], bomb.curorigin[ 1 ], bomb.curorigin[ 2 ] + 5 );
		
		// hang around the bomb if other is going to go get it
		if ( bomb.bots > 1 )
		{
			if ( self HasScriptGoal() )
			{
				return;
			}
			
			if ( distancesquared( origin, self.origin ) <= 1024 * 1024 )
			{
				return;
			}
			
			self SetScriptGoal( origin, 256 );
			
			self thread bot_get_obj( bomb );
			
			if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
			{
				self ClearScriptGoal();
			}
			
			return;
		}
		
		// go get the bomb
		self BotNotifyBotEvent( "sd", "start", "bomb" );
		
		self.bot_lock_goal = true;
		self SetScriptGoal( origin, 64 );
		self thread bot_inc_bots( bomb );
		self thread bot_get_obj( bomb );
		
		if ( self waittill_any_return( "goal", "bad_path", "new_goal" ) != "new_goal" )
		{
			self ClearScriptGoal();
		}
		
		self.bot_lock_goal = false;
		
		self BotNotifyBotEvent( "sd", "stop", "bomb" );
		return;
	}
	
	// check if to plant
	if ( timepassed < 120 && timeleft >= 90 && randomint( 100 ) < 98 )
	{
		return;
	}
	
	if ( !isdefined( level.bombzones ) || !level.bombzones.size )
	{
		return;
	}
	
	sites = [];
	
	for ( i = 0; i < level.bombzones.size; i++ )
	{
		sites[ sites.size ] = level.bombzones[ i ];
	}
	
	if ( !sites.size )
	{
		return;
	}
	
	if ( data.rand > 50 )
	{
		plant = self bot_array_nearest_curorigin( sites );
	}
	else
	{
		plant = random( sites );
	}
	
	if ( !isdefined( plant ) )
	{
		return;
	}
	
	origin = ( plant.curorigin[ 0 ] + 50, plant.curorigin[ 1 ] + 50, plant.curorigin[ 2 ] + 5 );
	
	self BotNotifyBotEvent( "sd", "go", "plant", plant );
	
	self.bot_lock_goal = true;
	self SetScriptGoal( origin, 1 );
	self thread bot_go_plant( plant );
	
	event = self waittill_any_return( "goal", "bad_path", "new_goal" );
	
	if ( event != "new_goal" )
	{
		self ClearScriptGoal();
	}
	
	urgent = timeleft < 20;
	
	if ( event != "goal" || level.bombplanted || plant.visibleteam == "none" || !self istouching( plant.trigger ) || self inLastStand() || ( self HasThreat() && !urgent ) || plant isInUse() )
	{
		self.bot_lock_goal = false;
		return;
	}
	
	self BotNotifyBotEvent( "sd", "start", "plant", plant );
	
	self BotRandomStance();
	self SetScriptGoal( self.origin, 64 );
	self bot_wait_stop_move();
	
	waitTime = ( plant.usetime / 1000 ) + 2.5;
	self thread BotPressUse( waitTime );
	wait waitTime;
	
	self ClearScriptGoal();
	self.bot_lock_goal = false;
	
	self BotNotifyBotEvent( "sd", "stop", "plant", plant );
}

/*
	Bots play sd attackers
*/
bot_sd_attackers()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	
	if ( level.gametype != "sd" )
	{
		return;
	}
	
	if ( self.team != game[ "attackers" ] )
	{
		return;
	}
	
	data = spawnstruct();
	data.rand = self BotGetRandom();
	data.first = true;
	
	for ( ;; )
	{
		self bot_sd_attackers_loop( data );
	}
}
