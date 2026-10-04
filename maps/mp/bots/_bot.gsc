#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\bots\_bot_utility;

/*
	Initiates the whole bot scripts.
*/
init()
{
	level.bw_version = "2.3.0";
	
	if ( getdvar( "bots_main" ) == "" )
	{
		setdvar( "bots_main", true );
	}
	
	if ( !getdvarint( "bots_main" ) )
	{
		return;
	}
	
	if ( !wait_for_builtins() )
	{
		println( "FATAL: NO BUILT-INS FOR BOTS" );
	}
	
	thread load_waypoints();
	level thread maps\mp\bots\_bot_navgen::navgen_probe_watch();
	level thread maps\mp\bots\_bot_internal::bot_gaze_load();
	cac_init_patch();
	thread hook_callbacks();
	
	if ( getdvar( "bots_main_GUIDs" ) == "" )
	{
		setdvar( "bots_main_GUIDs", "" ); // guids of players who will be given host powers, comma seperated
	}
	
	if ( getdvar( "bots_main_firstIsHost" ) == "" )
	{
		setdvar( "bots_main_firstIsHost", true ); // first player to connect is a host
	}
	
	if ( getdvar( "bots_main_waitForHostTime" ) == "" )
	{
		setdvar( "bots_main_waitForHostTime", 10.0 ); // how long to wait to wait for the host player
	}
	
	if ( getdvar( "bots_main_kickBotsAtEnd" ) == "" )
	{
		setdvar( "bots_main_kickBotsAtEnd", false ); // kicks the bots at game end
	}
	
	if ( getdvar( "bots_motor_model" ) == "" ) // bots move with the human movement state machine learned from demos (_bot_motor_data.gsc)
	{
		setdvar( "bots_motor_model", true );
	}
	
	if ( getdvar( "bots_telemetry" ) == "" ) // 5Hz movement lines (BT;) for every player in games_mp.log, for tools/movestats.py
	{
		setdvar( "bots_telemetry", 0 );
	}
	
	if ( getdvar( "bots_telemetry_out" ) == "" ) // 0 log only, 1 console only (unthrottled), 2 both
	{
		setdvar( "bots_telemetry_out", 0 );
	}
	
	// Measured WORSE with the unattended loop (13 tells vs 11 for the shipped build,
	// same human baseline): the view drift adds turns that humans do not make.
	// Kept as a knob, off by default.
	if ( getdvar( "bots_glance_wander" ) == "" )
	{
		setdvar( "bots_glance_wander", 0 );
	}
	
	if ( getdvar( "bots_idle_turn_slow" ) == "" ) // idle/casual turn slowdown, 1.0 = as-is
	{
		setdvar( "bots_idle_turn_slow", 1.0 );
	}	
	// Peak view-rate cap in deg/s (0 = off). Telemetry says our fastest view
	// changes are ~20% quicker than any human sample.
	// 450: verified over two pooled S&D matches per arm, this resolved
	// turn.rate_p99 (bot median 775 -> 415 deg/s against humans 410, from 0% to
	// 99% inside the human band) and turn.snap_p90/rate_p90/pitch_rate_p90 all
	// improved, with everything that moved the other way below the noise floor.
	// Set 0 to disable.
	
	// Mid-range turn rate is the remaining turn tell (yaw rate p90 225 deg/s against
	// humans 120 even with the peak capped). Two levers on it, both tunable so they
	// can be compared inside one build: how long an acquisition takes
	// (bots_acq_slow, was hardcoded 1.8) and how fast the view tracks afterwards
	// (bots_pursuit_gain, 1.0 = as shipped).
	
	// Prefer the calm path look over a "useful" sweep when a glance fails its
	// line-of-sight check (0 = as shipped, which is what the humanize pass tuned).
	
	// Share one timer between the gaze hold and the "useful" sweep hold, so the
	// view stops ping-ponging between them (0 = as shipped).
	
	// Seconds a failed look target must stay failed before the bot abandons it.
	// 0 = swap on the first bad tick (as shipped). 0.35 damped the flicker without
	// making the bot stare at walls for long.
	if ( getdvar( "bots_look_commit" ) == "" )
	{
		setdvar( "bots_look_commit", 0 );
	}
	if ( getdvar( "bots_look_hold" ) == "" )
	{
		setdvar( "bots_look_hold", 0 );
	}
	if ( getdvar( "bots_steady_look" ) == "" )
	{
		setdvar( "bots_steady_look", 0 );
	}
	// 2.2 (was hardcoded 1.8): three pooled S&D matches against a two-match
	// reference, scored through one path. OVERALL 47.6 -> 48.9, indistinct
	// 43% -> 46%, one tell resolved and none added, and a bootstrap on the
	// difference put 4 movements on the right side of zero against 2 on the
	// wrong (fire.shots_per_min, speed.p99, speed.accel_p90, path.dist_min).
	if ( getdvar( "bots_acq_slow" ) == "" )
	{
		setdvar( "bots_acq_slow", 2.2 );
	}
	if ( getdvar( "bots_pursuit_gain" ) == "" )
	{
		setdvar( "bots_pursuit_gain", 1.0 );
	}
	if ( getdvar( "bots_max_turn_rate" ) == "" )
	{
		setdvar( "bots_max_turn_rate", 450 );
	}
	
	// idle glance dwell: humans turn ~10+ deg 37.6 times a minute while idle,
	// i.e. a ~1.6s mean interval; the shipped 1200-3500ms averages ~2.3s.
	if ( getdvar( "bots_glance_dwell_lo" ) == "" )
	{
		setdvar( "bots_glance_dwell_lo", 1200 );
		setdvar( "bots_glance_dwell_hi", 3500 );
	}
	
	if ( getdvar( "bots_main_debug" ) == "" )
	{
		setdvar( "bots_main_debug", 0 ); // bot debug logging level: 0=off, 1=basic, 2=detailed
	}
	
	if ( getdvar( "bots_manage_add" ) == "" )
	{
		setdvar( "bots_manage_add", 0 ); // amount of bots to add to the game
	}
	
	if ( getdvar( "bots_manage_fill" ) == "" )
	{
		setdvar( "bots_manage_fill", 0 ); // amount of bots to maintain
	}
	
	if ( getdvar( "bots_manage_fill_spec" ) == "" )
	{
		setdvar( "bots_manage_fill_spec", true ); // to count for fill if player is on spec team
	}
	
	if ( getdvar( "bots_manage_fill_mode" ) == "" )
	{
		setdvar( "bots_manage_fill_mode", 0 ); // fill mode, 0 adds everyone, 1 just bots, 2 maintains at maps, 3 is 2 with 1
	}
	
	if ( getdvar( "bots_lobby_human" ) == "" ) // trickle joins, sessions/leaves, same bots carried across maps
	{
		setdvar( "bots_lobby_human", true );
	}
	
	if ( getdvar( "bots_manage_fill_kick" ) == "" )
	{
		setdvar( "bots_manage_fill_kick", false ); // kick bots if too many
	}
	
	if ( getdvar( "bots_manage_fill_watchplayers" ) == "" )
	{
		setdvar( "bots_manage_fill_watchplayers", false ); // add bots when player exists, kick if not
	}
	
	if ( getdvar( "bots_team" ) == "" )
	{
		setdvar( "bots_team", "autoassign" ); // which team for bots to join
	}
	
	if ( getdvar( "bots_team_amount" ) == "" )
	{
		setdvar( "bots_team_amount", 0 ); // amount of bots on axis team
	}
	
	if ( getdvar( "bots_team_force" ) == "" )
	{
		setdvar( "bots_team_force", false ); // force bots on team
	}
	
	if ( getdvar( "bots_team_mode" ) == "" )
	{
		setdvar( "bots_team_mode", 0 ); // counts just bots when 1
	}
	
	if ( getdvar( "bots_skill" ) == "" )
	{
		setdvar( "bots_skill", 0 ); // 0 is random, 1 is easy 7 is hard, 8 is custom, 9 is completely random
	}
	
	if ( getdvar( "bots_skill_axis_hard" ) == "" )
	{
		setdvar( "bots_skill_axis_hard", 0 ); // amount of hard bots on axis team
	}
	
	if ( getdvar( "bots_skill_axis_med" ) == "" )
	{
		setdvar( "bots_skill_axis_med", 0 );
	}
	
	if ( getdvar( "bots_skill_allies_hard" ) == "" )
	{
		setdvar( "bots_skill_allies_hard", 0 );
	}
	
	if ( getdvar( "bots_skill_allies_med" ) == "" )
	{
		setdvar( "bots_skill_allies_med", 0 );
	}
	
	if ( getdvar( "bots_skill_min" ) == "" )
	{
		setdvar( "bots_skill_min", 1 );
	}
	
	if ( getdvar( "bots_skill_max" ) == "" )
	{
		setdvar( "bots_skill_max", 7 );
	}
	
	if ( getdvar( "bots_loadout_reasonable" ) == "" ) // filter out the bad 'guns' and perks
	{
		setdvar( "bots_loadout_reasonable", false );
	}
	
	if ( getdvar( "bots_loadout_meta" ) == "" ) // weight loadouts like real public players (0 = uniform random)
	{
		setdvar( "bots_loadout_meta", true );
	}
	
	if ( getdvar( "bots_loadout_allow_op" ) == "" ) // allows jug, marty and laststand
	{
		setdvar( "bots_loadout_allow_op", true );
	}
	
	if ( getdvar( "bots_loadout_rank" ) == "" ) // what rank the bots should be around, -1 is around the players, 0 is all random
	{
		setdvar( "bots_loadout_rank", -1 );
	}
	
	if ( getdvar( "bots_loadout_prestige" ) == "" ) // what pretige the bots will be, -1 is the players, -2 is random
	{
		setdvar( "bots_loadout_prestige", -1 );
	}
	
	if ( getdvar( "bots_play_move" ) == "" ) // bots move
	{
		setdvar( "bots_play_move", true );
	}
	
	if ( getdvar( "bots_play_knife" ) == "" ) // bots knife
	{
		setdvar( "bots_play_knife", true );
	}
	
	if ( getdvar( "bots_play_fire" ) == "" ) // bots fire
	{
		setdvar( "bots_play_fire", true );
	}
	
	if ( getdvar( "bots_play_nade" ) == "" ) // bots grenade
	{
		setdvar( "bots_play_nade", true );
	}
	
	if ( getdvar( "bots_play_obj" ) == "" ) // bots play the obj
	{
		setdvar( "bots_play_obj", true );
	}
	
	if ( getdvar( "bots_play_camp" ) == "" ) // bots camp and follow
	{
		setdvar( "bots_play_camp", true );
	}
	
	if ( getdvar( "bots_play_jumpdrop" ) == "" ) // bots jump and dropshot
	{
		setdvar( "bots_play_jumpdrop", true );
	}
	
	if ( getdvar( "bots_play_target_other" ) == "" ) // bot target non play ents (vehicles)
	{
		setdvar( "bots_play_target_other", true );
	}
	
	if ( getdvar( "bots_play_killstreak" ) == "" ) // bot use killstreaks
	{
		setdvar( "bots_play_killstreak", true );
	}
	
	if ( getdvar( "bots_play_ads" ) == "" ) // bot ads
	{
		setdvar( "bots_play_ads", true );
	}
	
	if ( getdvar( "bots_play_aim" ) == "" )
	{
		setdvar( "bots_play_aim", true );
	}
	
	if ( getdvar( "bots_aim_recoil" ) == "" ) // bots simulate full-auto climb in their aim; off: A/B showed it pushed headshots 14% -> 21%. Enable only if killcams show laser sprays
	{
		setdvar( "bots_aim_recoil", false );
	}
	
	if ( !isdefined( game[ "botWarfare" ] ) )
	{
		game[ "botWarfare" ] = true;
		game[ "botWarfareInitTime" ] = gettime();
	}
	
	level.bot_inittime = gettime();
	
	level.defuseobject = undefined;
	level.bots_smokelist = List();
	level.tbl_perkdata[ 0 ][ "reference_full" ] = true;
	
	for ( h = 1; h < 6; h++ )
	{
		for ( i = 0; i < 3; i++ )
		{
			level.default_perk[ "CLASS_CUSTOM" + h ][ i ] = "specialty_null";
		}
	}
	
	level.bots_minsprintdistance = 315;
	level.bots_minsprintdistance *= level.bots_minsprintdistance;
	level.bots_mingrenadedistance = 256;
	level.bots_mingrenadedistance *= level.bots_mingrenadedistance;
	level.bots_maxgrenadedistance = 1024;
	level.bots_maxgrenadedistance *= level.bots_maxgrenadedistance;
	level.bots_maxknifedistance = 128;
	level.bots_maxknifedistance *= level.bots_maxknifedistance;
	level.bots_goaldistance = 27.5;
	level.bots_goaldistance *= level.bots_goaldistance;
	level.bots_noadsdistance = 200;
	level.bots_noadsdistance *= level.bots_noadsdistance;
	level.bots_maxshotgundistance = 500;
	level.bots_maxshotgundistance *= level.bots_maxshotgundistance;
	level.bots_listendist = 100;
	
	level.smokeradius = 255;
	
	level.bots = [];
	
	level.bots_fullautoguns = [];
	level.bots_fullautoguns[ "rpd" ] = true;
	level.bots_fullautoguns[ "m60e4" ] = true;
	level.bots_fullautoguns[ "saw" ] = true;
	level.bots_fullautoguns[ "ak74u" ] = true;
	level.bots_fullautoguns[ "mp5" ] = true;
	level.bots_fullautoguns[ "p90" ] = true;
	level.bots_fullautoguns[ "skorpion" ] = true;
	level.bots_fullautoguns[ "uzi" ] = true;
	level.bots_fullautoguns[ "g36c" ] = true;
	level.bots_fullautoguns[ "m4" ] = true;
	level.bots_fullautoguns[ "ak47" ] = true;
	level.bots_fullautoguns[ "mp44" ] = true;
	
	level thread fixGamemodes();
	level thread onUAVAlliesUpdate();
	level thread onUAVAxisUpdate();
	level thread chopperWatch();
	
	level thread onPlayerConnect();
	level thread handleBots();
	level thread onPlayerChat();
	level thread watchMarkDvar();
	
	array_thread( getentarray( "misc_turret", "classname" ), ::turret_monitoruse_watcher );
}

/*
	Starts the threads for bots.
*/
handleBots()
{
	loadLobbyCarry();
	level thread teamBots();
	level thread diffBots();
	level addBots();
	
	while ( !level.intermission )
	{
		wait 0.05;
	}
	
	setdvar( "bots_manage_add", getBotArray().size );
	
	if ( getdvarint( "bots_lobby_human" ) )
	{
		saveLobbyCarry();
		setdvar( "bots_manage_add", 0 ); // carried bots rejoin through the fill logic
	}
	
	if ( !getdvarint( "bots_main_kickBotsAtEnd" ) )
	{
		return;
	}
	
	bots = getBotArray();
	
	for ( i = 0; i < bots.size; i++ )
	{
		kick( bots[ i ] getentitynumber() );
	}
}

/*
	Saves the lobby at intermission so the same "players" reconnect next map
	(CoD4x drops test clients on map change). ~15% leave at map change.
	Record: name`persona`skill`lang`leadroll  (records joined with ~, - = unset)
*/
saveLobbyCarry()
{
	bots = getBotArray();
	out = "";
	
	for ( i = 0; i < bots.size; i++ )
	{
		bot = bots[ i ];
		
		if ( randomint( 100 ) < 15 || !isdefined( bot.pers[ "bots" ] ) )
		{
			continue;
		}
		
		rec = stripTrailingWhite( bot.name );
		rec += "`" + carryField( bot.pers[ "bots" ][ "persona" ] );
		rec += "`" + carryField( bot.pers[ "bots" ][ "skill" ][ "base" ] );
		rec += "`" + carryField( bot.pers[ "bots" ][ "chat_lang" ] );
		rec += "`" + carryField( bot.pers[ "bots" ][ "lead_frac_roll" ] );
		
		if ( out != "" )
		{
			out += "~";
		}
		
		out += rec;
	}
	
	setdvar( "bots_lobby_carry", out );
}

/*
	Drops trailing ^7 color resets so carried names don't grow each map.
*/
stripTrailingWhite( name )
{
	end = name.size;
	
	while ( end >= 2 && name[ end - 2 ] == "^" && name[ end - 1 ] == "7" )
	{
		end -= 2;
	}
	
	out = "";
	
	for ( i = 0; i < end; i++ )
	{
		out += name[ i ];
	}
	
	return out;
}

/*
	A carry field as text; "-" when unset (strtok drops empty fields).
*/
carryField( value )
{
	if ( !isdefined( value ) )
	{
		return "-";
	}
	
	return "" + value;
}

/*
	Reads the carried lobby for this map.
*/
loadLobbyCarry()
{
	level.bot_carry = [];
	
	if ( !getdvarint( "bots_lobby_human" ) || getdvar( "bots_lobby_carry" ) == "" )
	{
		return;
	}
	
	level.bot_carry = strtok( getdvar( "bots_lobby_carry" ), "~" );
	setdvar( "bots_lobby_carry", "" );
}

/*
	The hook callback for when any player becomes damaged.
*/
onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset )
{
	if ( self is_bot() )
	{
		self maps\mp\bots\_bot_internal::onDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
		self maps\mp\bots\_bot_script::onDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
	}
	
	self [[ level.prevcallbackplayerdamage ]]( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset );
}

/*
	The hook callback when any player gets killed.
*/
onPlayerKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration )
{
	if ( self is_bot() )
	{
		self maps\mp\bots\_bot_internal::onKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration );
		self maps\mp\bots\_bot_script::onKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration );
	}
	
	self.lastattacker = eAttacker;
	
	if ( isdefined( eAttacker ) )
	{
		eAttacker.lastkilledplayer = self;
		eAttacker notify( "killed_enemy" );
	}
	
	// every death is a fight spot, and nearby teammate bots react to it
	// (humans stop 77% of the time when a teammate drops within 1500u)
	bot_record_fight( self.origin );
	
	threat = undefined;
	
	if ( isdefined( eAttacker ) && isplayer( eAttacker ) && eAttacker != self )
	{
		threat = eAttacker.origin;
	}
	
	for ( i = 0; i < level.bots.size; i++ )
	{
		bot = level.bots[ i ];
		
		if ( !isdefined( bot ) || bot == self || !isalive( bot ) || !isdefined( bot.team ) || ( level.teambased && bot.team != self.team ) )
		{
			continue;
		}
		
		if ( distancesquared( bot.origin, self.origin ) < 1500 * 1500 )
		{
			bot thread maps\mp\bots\_bot_internal::botMateDown( self.origin, threat );
		}
	}
	
	self [[ level.prevcallbackplayerkilled ]]( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration );
}

/*
	Starts the callbacks.
*/
hook_callbacks()
{
	wait 0.05;
	level.prevcallbackplayerdamage = level.callbackplayerdamage;
	level.callbackplayerdamage = ::onPlayerDamage;
	
	level.prevcallbackplayerkilled = level.callbackplayerkilled;
	level.callbackplayerkilled = ::onPlayerKilled;
}

/*
	Adds the level.radio object for koth. Cause the iw3 script doesn't have it.
*/
fixKoth()
{
	level.radio = undefined;
	
	for ( ;; )
	{
		wait 0.05;
		
		if ( !isdefined( level.radioobject ) )
		{
			continue;
		}
		
		for ( i = level.radios.size - 1; i >= 0; i-- )
		{
			if ( level.radioobject != level.radios[ i ].gameobject )
			{
				continue;
			}
			
			level.radio = level.radios[ i ];
			break;
		}
		
		while ( isdefined( level.radioobject ) && level.radio.gameobject == level.radioobject )
		{
			wait 0.05;
		}
	}
}

/*
	Fixes gamemodes when level starts.
*/
fixGamemodes()
{
	for ( i = 0; i < 19; i++ )
	{
		if ( isdefined( level.bombzones ) && level.gametype == "sd" )
		{
			for ( i = 0; i < level.bombzones.size; i++ )
			{
				level.bombzones[ i ].onuse = ::onUsePlantObjectFix;
			}
			
			break;
		}
		
		if ( isdefined( level.radios ) && level.gametype == "koth" )
		{
			level thread fixKoth();
			
			break;
		}
		
		wait 0.05;
	}
}

/*
	Thread when any player connects. Starts the threads needed.
*/
onPlayerConnect()
{
	for ( ;; )
	{
		level waittill( "connected", player );
		
		player thread onGrenadeFire();
		player thread onWeaponFired();
		player thread doPlayerModelFix();
		player thread telemetryWatch();
		
		player thread connected();
	}
}

/*
	Movement telemetry for every player when bots_telemetry is on. Humans on the
	same server give the baseline. Format:
	BT;num;name;isbot;x;y;z;vx;vy;vz;pitch;yaw;stance;ads*10;hastarget;skill;weapon
*/
telemetryWatch()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 0.2;
		
		if ( !getdvarint( "bots_telemetry" ) || !isalive( self ) || self.sessionstate != "playing" )
		{
			continue;
		}
		
		isBot = 0;
		hasTarget = 0;
		skill = 0;
		
		if ( self is_bot() )
		{
			isBot = 1;
			
			if ( isdefined( self.pers[ "bots" ] ) && isdefined( self.pers[ "bots" ][ "skill" ][ "base" ] ) )
			{
				skill = self.pers[ "bots" ][ "skill" ][ "base" ];
			}
			
			if ( isdefined( self.bot ) && isdefined( self.bot.target ) )
			{
				hasTarget = 1;
			}
		}
		
		o = self.origin;
		v = self getvelocity();
		a = self getplayerangles();
		
		// what the view is on: distance to the first surface along it, or
		// -1 when it hits nothing (sky / out of the map)
		eye = self geteye();
		bt = bullettrace( eye, eye + anglestoforward( a ) * 8000, false, self );
		depth = int( distance( eye, bt[ "position" ] ) );
		
		if ( bt[ "fraction" ] >= 1 || bt[ "surfacetype" ] == "none" || bt[ "surfacetype" ] == "default" && bt[ "position" ][ 2 ] > eye[ 2 ] + 200 )
		{
			depth = -1;
		}
		
		lookSrc = "-";
		
		if ( isBot && isdefined( self.bot.look_src ) )
		{
			lookSrc = self.bot.look_src;
		}
		
		acqms = "-1";
		shots = 0;
		
		if ( !isdefined( self.bot ) )
		{
			// a real client does not always get the bot struct on this build, and an
			// undefined-struct read at 5 Hz for the one client type that can be in
			// the server is exactly what kills the game loop
			self.bot = spawnstruct();
			self.bot.fired_at = -999999;
			self.bot.shots = 0;
		}
		
		if ( isdefined( self.bot.target ) && isdefined( self.bot.target_switch_time ) )
		{
			acqms = int( gettime() - self.bot.target_switch_time );
		}
		
		line = "BT;" + self getentitynumber() + ";" + self.name + ";" + isBot + ";" + int( o[ 0 ] ) + ";" + int( o[ 1 ] ) + ";" + int( o[ 2 ] ) + ";" + int( v[ 0 ] ) + ";" + int( v[ 1 ] ) + ";" + int( v[ 2 ] ) + ";" + int( a[ 0 ] ) + ";" + int( a[ 1 ] ) + ";" + self getstance() + ";" + int( self playerads() * 10 ) + ";" + hasTarget + ";" + skill + ";" + self getcurrentweapon() + ";" + lookSrc + ";" + depth + ";" + int( ( gettime() - self.bot.fired_at ) * 1000 ) + ";" + acqms + ";" + shots + "\n";
		
		// CoD4X's games_mp.log writer drops all but ~5 lines a minute, which
		// leaves an unattended match unscorable. print() goes to the server
		// console, which is not throttled, so tools/botmatch.sh reads it from
		// the container log instead. bots_telemetry_out: 0 = log only (default),
		// 1 = console only, 2 = both.
		out = getdvarint( "bots_telemetry_out" );
		
		if ( out != 1 )
		{
			logprint( line );
		}
		
		if ( out )
		{
			print( line );
		}
	}
}

/*
	Fixes bots perks showing up in killcams and prevents bots from being kicked from old iw3 gsc script.
*/
fixPerksAndScriptKick()
{
	self endon( "disconnect" );
	
	self waittill( "spawned" );
	
	self.pers[ "isBot" ] = undefined;
	
	if ( !level.gameended )
	{
		level waittill ( "game_ended" );
	}
	
	self.pers[ "isBot" ] = true;
}

/*
	When a bot disconnects.
*/
onDisconnectPlayer()
{
	name = self.name;
	
	self waittill( "disconnect" );
	waittillframeend;
	
	for ( i = 0; i < level.bots.size; i++ )
	{
		bot = level.bots[ i ];
		bot BotNotifyBotEvent( "connection", "disconnected", self, name );
	}
}

/*
	When a bot disconnects.
*/
onDisconnect()
{
	self waittill( "disconnect" );
	
	level.bots = array_remove( level.bots, self );
}

/*
	Called when a player connects.
*/
connected()
{
	self endon( "disconnect" );
	
	for ( i = 0; i < level.bots.size; i++ )
	{
		bot = level.bots[ i ];
		bot BotNotifyBotEvent( "connection", "connected", self, self.name );
	}
	
	self thread onDisconnectPlayer();
	
	if ( !isdefined( self.pers[ "bot_host" ] ) )
	{
		self thread doHostCheck();
	}
	
	if ( !self is_bot() )
	{
		return;
	}
	
	if ( !isdefined( self.pers[ "isBot" ] ) )
	{
		// fast restart...
		self.pers[ "isBot" ] = true;
	}
	
	if ( !isdefined( self.pers[ "isBotWarfare" ] ) )
	{
		self.pers[ "isBotWarfare" ] = true;
		self thread added();
	}
	
	self thread fixPerksAndScriptKick();
	
	self thread maps\mp\bots\_bot_internal::connected();
	self thread maps\mp\bots\_bot_script::connected();
	
	level.bots[ level.bots.size ] = self;
	self thread onDisconnect();
	self thread watchBotDebugEvent();

	waittillframeend; // wait for waittills to process
	level notify( "bot_connected", self );
}

/*
	DEBUG
*/
watchBotDebugEvent()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "bot_event", msg, str, b, c, d, e, f, g );
		
		if ( getdvarint( "bots_main_debug" ) >= 2 )
		{
			big_str = "Bot Warfare debug: " + self.name + ": " + msg;
			
			if ( isdefined( str ) && isstring( str ) )
			{
				big_str += ", " + str;
			}
			
			if ( isdefined( b ) && isstring( b ) )
			{
				big_str += ", " + b;
			}
			
			if ( isdefined( c ) && isstring( c ) )
			{
				big_str += ", " + c;
			}
			
			if ( isdefined( d ) && isstring( d ) )
			{
				big_str += ", " + d;
			}
			
			if ( isdefined( e ) && isstring( e ) )
			{
				big_str += ", " + e;
			}
			
			if ( isdefined( f ) && isstring( f ) )
			{
				big_str += ", " + f;
			}
			
			if ( isdefined( g ) && isstring( g ) )
			{
				big_str += ", " + g;
			}
			
			BotBuiltinPrintConsole( big_str );
			
			// Also output to chat for visibility in Docker logs
			if ( isdefined( self ) && isdefined( self.name ) )
			{
				debug_msg = "DEBUG_EVENT: " + self.name + " - " + msg;
				if ( isdefined( str ) )
				{
					debug_msg += " (" + str + ")";
				}
				self sayall( debug_msg );
			}
		}
		else if ( msg == "debug" && getdvarint( "bots_main_debug" ) >= 1 )
		{
			BotBuiltinPrintConsole( "Bot Warfare debug: " + self.name + ": " + str );
		}
	}
}

/*
	When a bot gets added into the game.
*/
added()
{
	self endon( "disconnect" );
	
	self thread maps\mp\bots\_bot_internal::added();
	self thread maps\mp\bots\_bot_script::added();
}

/*
	Adds a bot to the game.
*/
add_bot()
{
	// cod4x specific
	carry = undefined;
	
	if ( isdefined( level.bot_carry ) && level.bot_carry.size )
	{
		carry = strtok( level.bot_carry[ level.bot_carry.size - 1 ], "`" );
		level.bot_carry[ level.bot_carry.size - 1 ] = undefined;
		name = carry[ 0 ];
	}
	else
	{
		name = getABotName();
	}
	
	bot = undefined;
	
	if ( isdefined( name ) && name.size >= 3 )
	{
		bot = addtestclient( name );
	}
	else
	{
		bot = addtestclient();
	}
	
	if ( isdefined( bot ) )
	{
		bot.pers[ "isBot" ] = true;
		bot.pers[ "isBotWarfare" ] = true;
		bot.bot_carry = carry;
		bot thread added();
	}
}

/*
	A server thread for monitoring all bot's difficulty levels for custom server settings.
*/
diffBots_loop()
{
	var_allies_hard = getdvarint( "bots_skill_allies_hard" );
	var_allies_med = getdvarint( "bots_skill_allies_med" );
	var_axis_hard = getdvarint( "bots_skill_axis_hard" );
	var_axis_med = getdvarint( "bots_skill_axis_med" );
	var_skill = getdvarint( "bots_skill" );
	
	allies_hard = 0;
	allies_med = 0;
	axis_hard = 0;
	axis_med = 0;
	
	if ( var_skill == 8 )
	{
		playercount = level.players.size;
		
		for ( i = 0; i < playercount; i++ )
		{
			player = level.players[ i ];
			
			if ( !isdefined( player.pers[ "team" ] ) )
			{
				continue;
			}
			
			if ( !player is_bot() )
			{
				continue;
			}
			
			if ( player.pers[ "team" ] == "axis" )
			{
				if ( axis_hard < var_axis_hard )
				{
					axis_hard++;
					player.pers[ "bots" ][ "skill" ][ "base" ] = 7;
				}
				else if ( axis_med < var_axis_med )
				{
					axis_med++;
					player.pers[ "bots" ][ "skill" ][ "base" ] = 4;
				}
				else
				{
					player.pers[ "bots" ][ "skill" ][ "base" ] = 1;
				}
			}
			else if ( player.pers[ "team" ] == "allies" )
			{
				if ( allies_hard < var_allies_hard )
				{
					allies_hard++;
					player.pers[ "bots" ][ "skill" ][ "base" ] = 7;
				}
				else if ( allies_med < var_allies_med )
				{
					allies_med++;
					player.pers[ "bots" ][ "skill" ][ "base" ] = 4;
				}
				else
				{
					player.pers[ "bots" ][ "skill" ][ "base" ] = 1;
				}
			}
		}
	}
	else if ( var_skill != 0 && var_skill != 9 )
	{
		playercount = level.players.size;
		
		for ( i = 0; i < playercount; i++ )
		{
			player = level.players[ i ];
			
			if ( !player is_bot() )
			{
				continue;
			}
			
			player.pers[ "bots" ][ "skill" ][ "base" ] = var_skill;
		}
	}
	
	playercount = level.players.size;
	min_diff = getdvarint( "bots_skill_min" );
	max_diff = getdvarint( "bots_skill_max" );
	
	for ( i = 0; i < playercount; i++ )
	{
		player = level.players[ i ];
		
		if ( !player is_bot() )
		{
			continue;
		}
		
		player.pers[ "bots" ][ "skill" ][ "base" ] = int( clamp( player.pers[ "bots" ][ "skill" ][ "base" ], min_diff, max_diff ) );
	}
}

/*
	A server thread for monitoring all bot's difficulty levels for custom server settings.
*/
diffBots()
{
	for ( ;; )
	{
		wait 1.5;
		
		diffBots_loop();
	}
}

/*
	A server thread for monitoring all bot's teams for custom server settings.
*/
teamBots_loop()
{
	teamAmount = getdvarint( "bots_team_amount" );
	toTeam = getdvar( "bots_team" );
	
	alliesbots = 0;
	alliesplayers = 0;
	axisbots = 0;
	axisplayers = 0;
	
	playercount = level.players.size;
	
	for ( i = 0; i < playercount; i++ )
	{
		player = level.players[ i ];
		
		if ( !isdefined( player.pers[ "team" ] ) )
		{
			continue;
		}
		
		if ( player is_bot() )
		{
			if ( player.pers[ "team" ] == "allies" )
			{
				alliesbots++;
			}
			else if ( player.pers[ "team" ] == "axis" )
			{
				axisbots++;
			}
		}
		else
		{
			if ( player.pers[ "team" ] == "allies" )
			{
				alliesplayers++;
			}
			else if ( player.pers[ "team" ] == "axis" )
			{
				axisplayers++;
			}
		}
	}
	
	allies = alliesbots;
	axis = axisbots;
	
	if ( !getdvarint( "bots_team_mode" ) )
	{
		allies += alliesplayers;
		axis += axisplayers;
	}
	
	if ( toTeam != "custom" )
	{
		if ( getdvarint( "bots_team_force" ) )
		{
			if ( toTeam == "autoassign" )
			{
				if ( abs( axis - allies ) > 1 )
				{
					toTeam = "axis";
					
					if ( axis > allies )
					{
						toTeam = "allies";
					}
				}
			}
			
			if ( toTeam != "autoassign" )
			{
				playercount = level.players.size;
				
				for ( i = 0; i < playercount; i++ )
				{
					player = level.players[ i ];
					
					if ( !isdefined( player.pers[ "team" ] ) )
					{
						continue;
					}
					
					if ( !player is_bot() )
					{
						continue;
					}
					
					if ( player.pers[ "team" ] == toTeam )
					{
						continue;
					}
					
					if ( toTeam == "allies" )
					{
						player thread [[ level.allies ]]();
					}
					else if ( toTeam == "axis" )
					{
						player thread [[ level.axis ]]();
					}
					else
					{
						player thread [[ level.spectator ]]();
					}
					
					break;
				}
			}
		}
	}
	else
	{
		playercount = level.players.size;
		
		for ( i = 0; i < playercount; i++ )
		{
			player = level.players[ i ];
			
			if ( !isdefined( player.pers[ "team" ] ) )
			{
				continue;
			}
			
			if ( !player is_bot() )
			{
				continue;
			}
			
			if ( player.pers[ "team" ] == "axis" )
			{
				if ( axis > teamAmount )
				{
					player thread [[ level.allies ]]();
					break;
				}
			}
			else
			{
				if ( axis < teamAmount )
				{
					player thread [[ level.axis ]]();
					break;
				}
				else if ( player.pers[ "team" ] != "allies" )
				{
					player thread [[ level.allies ]]();
					break;
				}
			}
		}
	}
}

/*
	A server thread for monitoring all bot's teams for custom server settings.
*/
teamBots()
{
	for ( ;; )
	{
		wait 1.5;
		
		teamBots_loop();
	}
}

/*
	A server thread for monitoring all bot's in game. Will add and kick bots according to server settings.
*/
addBots_loop()
{
	botsToAdd = getdvarint( "bots_manage_add" );
	
	if ( botsToAdd > 0 )
	{
		setdvar( "bots_manage_add", 0 );
		
		if ( botsToAdd > 64 )
		{
			botsToAdd = 64;
		}
		
		if ( getdvarint( "bots_lobby_human" ) )
		{
			// people trickle in; players from the last map reconnect quickly
			if ( !isdefined( level.bot_next_join ) || gettime() >= level.bot_next_join )
			{
				level add_bot();
				
				if ( isdefined( level.bot_carry ) && level.bot_carry.size )
				{
					level.bot_next_join = gettime() + randomintrange( 300, 2500 );
				}
				else
				{
					level.bot_next_join = gettime() + randomintrange( 4000, 20000 );
				}
			}
		}
		else
		{
			for ( ; botsToAdd > 0; botsToAdd-- )
			{
				level add_bot();
				wait 0.25;
			}
		}
	}
	
	fillMode = getdvarint( "bots_manage_fill_mode" );
	
	if ( fillMode == 2 || fillMode == 3 || fillMode == 5 )
	{
		setdvar( "bots_manage_fill", getGoodMapAmount() );
	}
	
	fillAmount = getdvarint( "bots_manage_fill" );
	
	// real lobbies breathe: population drifts a little every few minutes
	if ( getdvarint( "bots_lobby_human" ) && fillAmount > 4 )
	{
		if ( !isdefined( level.bot_fill_offset_until ) || gettime() > level.bot_fill_offset_until )
		{
			level.bot_fill_offset = randomintrange( -2, 2 );
			level.bot_fill_offset_until = gettime() + randomintrange( 180000, 360000 );
		}
		
		fillAmount += level.bot_fill_offset;
	}
	
	players = 0;
	bots = 0;
	spec = 0;
	axisplayers = 0;
	alliesplayers = 0;
	
	playercount = level.players.size;
	
	for ( i = 0; i < playercount; i++ )
	{
		player = level.players[ i ];
		
		if ( player is_bot() )
		{
			bots++;
		}
		else if ( !isdefined( player.pers[ "team" ] ) || ( player.pers[ "team" ] != "axis" && player.pers[ "team" ] != "allies" ) )
		{
			spec++;
		}
		else
		{
			players++;
			
			if ( player.pers[ "team" ] == "axis" )
			{
				axisplayers++;
			}
			else if ( player.pers[ "team" ] == "allies" )
			{
				alliesplayers++;
			}
		}
	}
	
	if ( getdvarint( "bots_manage_fill_spec" ) )
	{
		players += spec;
	}
	
	if ( !randomint( 999 ) )
	{
		setdvar( "testclients_doreload", true );
		wait 0.1;
		setdvar( "testclients_doreload", false );
		doExtraCheck();
	}
	
	amount = bots;
	
	if ( fillMode == 0 || fillMode == 2 )
	{
		amount += players;
	}
	
	// use bots as balance
	if ( fillMode == 4 || fillMode == 5 )
	{
		diffPlayers = abs( alliesplayers - axisplayers );
		amount = fillAmount - ( diffPlayers - bots );
		
		if ( players + diffPlayers < fillAmount )
		{
			amount = players + bots;
		}
	}
	
	if ( players <= 0 && getdvarint( "bots_manage_fill_watchplayers" ) )
	{
		amount = fillAmount + bots;
	}
	
	if ( amount < fillAmount )
	{
		setdvar( "bots_manage_add", fillAmount - amount );
	}
	else if ( amount > fillAmount && getdvarint( "bots_manage_fill_kick" ) )
	{
		botsToKick = amount - fillAmount;
		
		if ( botsToKick > 64 )
		{
			botsToKick = 64;
		}
		
		for ( i = 0; i < botsToKick; i++ )
		{
			tempBot = getBotToKick();
			
			if ( isdefined( tempBot ) )
			{
				kick( tempBot getentitynumber(), "EXE_PLAYERKICKED" );
				
				wait 0.25;
			}
		}
	}
}

/*
	A server thread for monitoring all bot's in game. Will add and kick bots according to server settings.
*/
addBots()
{
	level endon( "game_ended" );
	
	bot_wait_for_host();

	// a navmesh being generated for this map: bots would have nowhere to go
	while ( isdefined( level.bot_nav_generating ) && level.bot_nav_generating )
	{
		wait 0.5;
	}

	for ( ;; )
	{
		wait 1.5;

		addBots_loop();
	}
}

/*
	A thread for ALL players, will monitor and grenades thrown.
*/
onGrenadeFire()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill ( "grenade_fire", grenade, weaponName );
		
		if ( !isdefined( grenade ) )
		{
			continue;
		}
		
		grenade.name = weaponName;
		
		if ( weaponName == "smoke_grenade_mp" )
		{
			grenade thread AddToSmokeList();
		}
	}
}

/*
	Adds a smoke grenade to the list of smokes in the game. Used to prevent bots from seeing through smoke.
*/
AddToSmokeList()
{
	grenade = spawnstruct();
	grenade.origin = self getorigin();
	grenade.state = "moving";
	grenade.grenade = self;
	
	grenade thread thinkSmoke();
	
	level.bots_smokelist ListAdd( grenade );
}

/*
	The smoke grenade logic.
*/
thinkSmoke()
{
	while ( isdefined( self.grenade ) )
	{
		self.origin = self.grenade getorigin();
		self.state = "moving";
		wait 0.05;
	}
	
	self.state = "smoking";
	wait 11.5;
	
	level.bots_smokelist ListRemove( self );
}

/*
	Watches for chopper. This is used to fix bots from targeting leaving or crashing helis because script is iw3 old and buggy.
*/
chopperWatch()
{
	for ( ;; )
	{
		while ( !isdefined( level.chopper ) )
		{
			wait 0.05;
		}
		
		chopper = level.chopper;
		
		if ( level.teambased && getdvarint( "doubleHeli" ) )
		{
			chopper = level.chopper[ "allies" ];
			
			if ( !isdefined( chopper ) )
			{
				chopper = level.chopper[ "axis" ];
			}
		}
		
		level.bot_chopper = true;
		chopper watchChopper();
		level.bot_chopper = false;
		
		while ( isdefined( level.chopper ) )
		{
			wait 0.05;
		}
	}
}

/*
	Waits until the chopper is deleted, leaving or crashing.
*/
watchChopper()
{
	self endon( "death" );
	self endon( "leaving" );
	self endon( "crashing" );
	
	level waittill( "helicopter gone" );
}

/*
	Waits when the axis uav is called in.
*/
onUAVAxisUpdate()
{
	for ( ;; )
	{
		level waittill( "radar_timer_kill_axis" );
		level thread doUAVUpdate( "axis" );
	}
}

/*
	Waits when the allies uav is called in.
*/
onUAVAlliesUpdate()
{
	for ( ;; )
	{
		level waittill( "radar_timer_kill_allies" );
		level thread doUAVUpdate( "allies" );
	}
}

/*
	Updates the player's radar so bots can know when they have a uav up, because iw3 script is old.
*/
doUAVUpdate( team )
{
	level endon( "radar_timer_kill_" + team );
	
	playercount = level.players.size;
	
	for ( i = 0; i < playercount; i++ )
	{
		player = level.players[ i ];
		
		if ( !isdefined( player.team ) )
		{
			continue;
		}
		
		if ( player.team == team )
		{
			player.bot_radar = true;
		}
	}
	
	wait level.radarviewtime;
	
	playercount = level.players.size;
	
	for ( i = 0; i < playercount; i++ )
	{
		player = level.players[ i ];
		
		if ( !isdefined( player.team ) )
		{
			continue;
		}
		
		if ( player.team == team )
		{
			player.bot_radar = false;
		}
	}
}

/*
	Fixes a weird iw3 bug when for a frame the player doesn't have any bones when they first spawn in.
*/
doPlayerModelFix()
{
	self endon( "disconnect" );
	self waittill( "spawned_player" );
	wait 0.05;
	self.bot_model_fix = true;
}

/*
	A thread for ALL players when they fire.
*/
onWeaponFired()
{
	self endon( "disconnect" );
	self.bots_firing = false;
	
	for ( ;; )
	{
		self waittill( "weapon_fired" );
		if ( isdefined( self.bot ) )
		{
			self.bot.fired_at = gettime();
		}

		self thread doFiringThread();
		
		// remember audible (unsilenced) gunfire for bots' hearing
		weap = self getcurrentweapon();
		
		if ( !issubstr( weap, "silencer" ) )
		{
			bot_record_shot( self.origin, self.team );
		}
	}
}

/*
	Lets bot's know that the player is firing.
*/
doFiringThread()
{
	self endon( "disconnect" );
	self endon( "weapon_fired" );
	self.bots_firing = true;
	wait 1;
	self.bots_firing = false;
}

/*
	When a player chats
*/
onPlayerChat()
{
	for ( ;; )
	{
		level waittill( "say", message, player, is_hidden );
		
		// feedback marks from a human watching: "!look", "!move", "!stuck",
		// "!nade", "!dumb", "!ok" -> log the watched bot's full state
		// (chat text can carry a leading control character: take what follows the "!")
		cmd = "";
		bang = strtok( message, "!" );
		
		if ( bang.size && bang[ bang.size - 1 ] != message )
		{
			words = strtok( bang[ bang.size - 1 ], " " );
			
			if ( words.size )
			{
				cmd = "!" + words[ 0 ];
			}
		}
		
		if ( isdefined( player ) && !player is_bot() && ( cmd == "!look" || cmd == "!move" || cmd == "!stuck" || cmd == "!nade" || cmd == "!dumb" || cmd == "!ok" ) )
		{
			player thread markWatchedBot( getsubstr_first( cmd ) );
			continue;
		}
		
		for ( i = 0; i < level.bots.size; i++ )
		{
			bot = level.bots[ i ];
			
			bot BotNotifyBotEvent( "chat", "chat", message, player, is_hidden );
		}
	}
}

/*
	CoD4x doesn't pass chat to scripts, so tools/markwatch.py tails the log
	for "!look"-style chat and sets bots_mark "<client number> <category>".
*/
watchMarkDvar()
{
	setdvar( "bots_mark", "" );
	
	for ( ;; )
	{
		wait 0.1;
		v = getdvar( "bots_mark" );
		
		if ( v == "" )
		{
			continue;
		}
		
		setdvar( "bots_mark", "" );
		t = strtok( v, " " );
		
		if ( t.size < 2 )
		{
			continue;
		}
		
		for ( i = 0; i < level.players.size; i++ )
		{
			if ( level.players[ i ] getentitynumber() == int( t[ 0 ] ) )
			{
				level.players[ i ] thread markWatchedBot( t[ 1 ] );
			}
		}
	}
}

/*
	Mark category without the leading "!".
*/
getsubstr_first( cmd )
{
	switch ( cmd )
	{
		case "!look":
			return "look";
			
		case "!move":
			return "move";
			
		case "!stuck":
			return "stuck";
			
		case "!nade":
			return "nade";
			
		case "!dumb":
			return "dumb";
	}
	
	return "ok";
}

/*
	Called on a human who marked a moment: finds the bot they're watching
	(the one nearest the centre of their view, or nearest them when
	following one as a spectator) and logs its full state as a MARK line.
*/
markWatchedBot( cat )
{
	eye = self geteye();
	fwd = anglestoforward( self getplayerangles() );
	best = undefined;
	bestScore = -1;
	
	for ( i = 0; i < level.bots.size; i++ )
	{
		bot = level.bots[ i ];
		
		if ( !isalive( bot ) || !isdefined( bot.bot ) )
		{
			continue;
		}
		
		d = distance( eye, bot.origin );
		
		// following a bot: the camera sits on it
		if ( d < 120 )
		{
			best = bot;
			break;
		}
		
		dot = vectordot( fwd, vectornormalize( bot.origin + ( 0, 0, 40 ) - eye ) );
		
		if ( dot > 0.9 && dot > bestScore )
		{
			bestScore = dot;
			best = bot;
		}
	}
	
	if ( !isdefined( best ) )
	{
		self iprintln( "^1No bot in view to mark" );
		return;
	}
	
	b = best.bot;
	o = best.origin;
	a = best getplayerangles();
	v = best getvelocity();
	beye = best geteye();
	bt = bullettrace( beye, beye + anglestoforward( a ) * 8000, false, best );
	
	look = "-";
	motor = "-";
	roam = "-";
	goal = "-";
	target = 0;
	
	if ( isdefined( b.look_src ) )
	{
		look = b.look_src;
	}
	
	if ( isdefined( b.motor_state ) )
	{
		motor = b.motor_state;
	}
	
	if ( isdefined( b.roam_reason ) )
	{
		roam = b.roam_reason;
	}
	
	if ( isdefined( b.script_goal ) )
	{
		goal = "script " + int( b.script_goal[ 0 ] ) + " " + int( b.script_goal[ 1 ] ) + " " + int( b.script_goal[ 2 ] );
	}
	
	if ( isdefined( b.target ) )
	{
		target = 1;
	}
	
	logprint( "MARK;" + cat + ";" + best getentitynumber() + ";" + best.name + ";" + int( o[ 0 ] ) + ";" + int( o[ 1 ] ) + ";" + int( o[ 2 ] ) + ";" + int( a[ 0 ] ) + ";" + int( a[ 1 ] ) + ";" + int( length_2d( v ) ) + ";" + best getstance() + ";" + int( best playerads() * 10 ) + ";" + int( distance( beye, bt[ "position" ] ) ) + ";" + look + ";" + motor + ";" + roam + ";" + goal + ";" + b.next_wp + ";" + target + ";" + b.climbing + "\n" );
	self iprintln( "Marked ^3" + best.name + "^7 (" + cat + "): look=" + look + " move=" + motor + " goal=" + roam );
}

/*
	Horizontal speed of a velocity.
*/
length_2d( v )
{
	return sqrt( v[ 0 ] * v[ 0 ] + v[ 1 ] * v[ 1 ] );
}

/*
	Monitors turret usage
*/
turret_monitoruse_watcher()
{
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill ( "trigger", player );
		
		self monitor_player_turret( player );
		
		self.owner = undefined;
		
		if ( isdefined( player ) )
		{
			player.turret = undefined;
		}
	}
}

/*
	While player uses turret
*/
monitor_player_turret( player )
{
	player endon( "death" );
	player endon( "disconnect" );
	
	player.turret = self;
	self.owner = player;
	
	while ( isdefined( player ) && player usebuttonpressed() )
	{
		wait 0.05;
	}
	
	while ( isdefined( player ) && !player usebuttonpressed() )
	{
		wait 0.05;
	}
}
