#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\bots\_bot_utility;

/*
	When a bot is added (once ever) to the game (before connected).
	We init all the persistent variables here.
*/
added()
{
	self endon( "disconnect" );
	
	self.pers[ "bots" ] = [];
	
	self.pers[ "bots" ][ "skill" ] = [];
	self.pers[ "bots" ][ "skill" ][ "base" ] = 7; // a base knownledge of the bot
	self.pers[ "bots" ][ "skill" ][ "aim_time" ] = 0.05; // how long it takes for a bot to aim to a location
	self.pers[ "bots" ][ "skill" ][ "init_react_time" ] = 0; // the reaction time of the bot for inital targets
	self.pers[ "bots" ][ "skill" ][ "reaction_time" ] = 0; // reaction time for the bots of reoccuring targets
	self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ] = 2500; // how long a bot ads's when they cant see the target
	self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ] = 10000; // how long a bot will look at a target's last position
	self.pers[ "bots" ][ "skill" ][ "remember_time" ] = 25000; // how long a bot will remember a target before forgetting about it when they cant see the target
	self.pers[ "bots" ][ "skill" ][ "fov" ] = -1; // the fov of the bot, -1 being 360, 1 being 0
	self.pers[ "bots" ][ "skill" ][ "dist_max" ] = 100000 * 2; // the longest distance a bot will target
	self.pers[ "bots" ][ "skill" ][ "dist_start" ] = 100000; // the start distance before bot's target abilitys diminish
	self.pers[ "bots" ][ "skill" ][ "spawn_time" ] = 0; // how long a bot waits after spawning before targeting, etc
	self.pers[ "bots" ][ "skill" ][ "help_dist" ] = 10000; // how far a bot has awareness
	self.pers[ "bots" ][ "skill" ][ "semi_time" ] = 0.05; // how fast a bot shoots semiauto
	self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ] = 1; // how long a bot shoots after target dies/cant be seen
	self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] = 1; // how long a bot correct's their aim after targeting
	self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ] = 1; // how far a bot's incorrect aim is
	self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] = 0.05; // how often a bot changes their bone target
	self.pers[ "bots" ][ "skill" ][ "bones" ] = "j_head"; // a list of comma seperated bones the bot will aim at
	self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ] = 0.5; // a factor of how much ads to reduce when adsing
	self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ] = 0.5; // a factor of how much more aimspeed delay to add
	self.pers[ "bots" ][ "skill" ][ "aim_jitter" ] = 0.3; // per-tick aim noise (degrees), human hand shake
	self.pers[ "bots" ][ "skill" ][ "overshoot" ] = 15; // percentage chance the flick overshoots and must correct
	self.pers[ "bots" ][ "skill" ][ "trigger_delay" ] = 120; // extra ms of trigger discipline after on-target (ms)
	self.pers[ "bots" ][ "skill" ][ "switch_penalty" ] = 250; // ms cost to switch targets, humans can't snap-swap
	self.pers[ "bots" ][ "skill" ][ "periph_bonus" ] = 0.08; // effective FOV widen for moving/firing targets
	self.pers[ "bots" ][ "skill" ][ "lead_frac" ] = 0.8; // how much of its own tracking lag the bot leads out on movers
	
	self.pers[ "bots" ][ "behavior" ] = [];
	self.pers[ "bots" ][ "behavior" ][ "strafe" ] = 50; // percentage of how often the bot strafes a target
	self.pers[ "bots" ][ "behavior" ][ "nade" ] = 50; // percentage of how often the bot will grenade
	self.pers[ "bots" ][ "behavior" ][ "sprint" ] = 50; // percentage of how often the bot will sprint
	self.pers[ "bots" ][ "behavior" ][ "camp" ] = 50; // percentage of how often the bot will camp
	self.pers[ "bots" ][ "behavior" ][ "follow" ] = 50; // percentage of how often the bot will follow
	self.pers[ "bots" ][ "behavior" ][ "crouch" ] = 10; // percentage of how often the bot will crouch
	self.pers[ "bots" ][ "behavior" ][ "switch" ] = 1; // percentage of how often the bot will switch weapons
	self.pers[ "bots" ][ "behavior" ][ "class" ] = 1; // percentage of how often the bot will change classes
	self.pers[ "bots" ][ "behavior" ][ "jump" ] = 100; // percentage of how often the bot will jumpshot and dropshot
	
	self.pers[ "bots" ][ "behavior" ][ "quickscope" ] = false; // is a quickscoper
	self.pers[ "bots" ][ "behavior" ][ "initswitch" ] = 10; // percentage of how often the bot will switch weapons on spawn
}

/*
	When a bot connects to the game.
	This is called when a bot is added and when multiround gamemode starts.
*/
connected()
{
	self endon( "disconnect" );
	
	self.bot = spawnstruct();
	self.bot_radar = false;
	self resetBotVars();
	
	self thread onPlayerSpawned();
	self thread bot_skip_killcam();
	self thread onUAVUpdate();
}

/*
	The thread for when the UAV gets updated.
*/
onUAVUpdate()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "radar_timer_kill" );
		self thread doUAVUpdate();
	}
}

/*
	We tell that bot has a UAV.
*/
doUAVUpdate()
{
	self endon( "disconnect" );
	self endon( "radar_timer_kill" );
	
	self.bot_radar = true; // wtf happened to hasRadar? its bugging out, something other than script is touching it
	
	wait level.radarviewtime;
	
	self.bot_radar = false;
}

/*
	The callback hook for when the bot gets killed.
*/
onKilled( eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, timeOffset, deathAnimDuration )
{
}

/*
	The callback hook when the bot gets damaged.
*/
onDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset )
{
	if ( !isdefined( self.bot ) )
	{
		return;
	}

	self.bot.last_damage_time = gettime();
	self.bot.last_damage_attacker = eAttacker;
}

/*
	We clear all of the script variables and other stuff for the bots.
*/
resetBotVars()
{
	self.bot.script_target = undefined;
	self.bot.script_target_offset = undefined;
	self.bot.target = undefined;
	self.bot.targets = [];
	self.bot.target_this_frame = undefined;
	self.bot.after_target = undefined;
	self.bot.after_target_pos = undefined;
	self.bot.moveto = self.origin;
	
	self.bot.script_aimpos = undefined;
	
	self.bot.script_goal = undefined;
	self.bot.script_goal_dist = 0.0;
	
	self.bot.next_wp = -1;
	self.bot.second_next_wp = -1;
	self.bot.towards_goal = undefined;
	self.bot.astar = [];
	self.bot.stop_move = false;
	self.bot.greedy_path = false;
	self.bot.wantsprint = false;
	self.bot.climbing = false;
	self.bot.last_next_wp = -1;
	self.bot.last_second_next_wp = -1;
	
	self.bot.isfrozen = false;
	self.bot.sprintendtime = -1;
	self.bot.isreloading = false;
	self.bot.issprinting = false;
	self.bot.isfragging = false;
	self.bot.issmoking = false;
	self.bot.isfraggingafter = false;
	self.bot.issmokingafter = false;
	self.bot.isknifing = false;
	self.bot.isknifingafter = false;
	self.bot.knifing_target = undefined;
	
	self.bot.semi_time = false;
	self.bot.jump_time = undefined;
	self.bot.last_fire_time = -1;
	
	self.bot.is_cur_full_auto = false;
	self.bot.cur_weap_dist_multi = 1;
	self.bot.is_cur_sniper = false;
	
	self.bot.prio_objective = false;
	
	self.bot.rand = randomint( 100 );

	self.bot.last_damage_time = 0;
	self.bot.last_damage_attacker = undefined;
	self.bot.target_switch_time = 0;
	self.bot.aim_ang = undefined;
	self.bot.aim_fired_time = undefined;
	self.bot.preaim_bonus_until = 0;
	self.bot.cautious = false;
	self.bot.glance_until = 0;
	self.bot.glance_next = 0;
	self.bot.glance_pos = undefined;
	self.bot.spawn_origin = self.origin;
	self.bot.spawn_time = gettime();
	self.bot.fight_crouch = false;
	self.bot.pistol_swap = false;
	self.bot.hear_delay = undefined;
	self.bot.juke_until = 0;
	self.bot.goal_view_yaw = undefined;
	self.bot.goal_cell = undefined;
	
	self BotBuiltinBotStop();
}

/*
	Bots will skip killcams here.
*/
bot_skip_killcam()
{
	level endon( "game_ended" );
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( isdefined( self.killcam ) )
		{
			self notify( "end_killcam" );
		}
	}
}

/*
	When the bot spawns.
*/
onPlayerSpawned()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		self waittill( "spawned_player" );
		
		self resetBotVars();
		self thread onWeaponChange();
		self thread onLastStand();
		
		self thread reload_watch();
		self thread sprint_watch();
		
		self thread spawned();
	}
}

/*
	We wait for a time defined by the bot's difficulty and start all threads that control the bot.
*/
spawned()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	wait self.pers[ "bots" ][ "skill" ][ "spawn_time" ];
	
	self thread grenade_danger();
	self thread check_reload();
	self thread stance();
	self thread botWalkAfterStart();
	self thread target();
	self thread updateBones();
	self thread aim();
	self thread motorController();
	self thread watchHoldBreath();
	self thread onNewEnemy();
	self thread doBotMovement();
	self thread watchGrenadeFire();
	self thread watchPickupGun();
	
	self notify( "bot_spawned" );
}

/*
	S&D: people leave spawn at different moments each round (demos: human exit
	spread IQR 0.2s, p90 1.1s; bots all left on the same tick every round).
*/
botWalkAfterStart()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	if ( level.gametype == "sd" )
	{
		while ( level.inprematchperiod || self.bot.isfrozen )
		{
			wait 0.05;
		}
		
		d = randomfloatrange( 0.05, 0.6 );
		
		if ( randomint( 100 ) < 12 )
		{
			d += randomfloatrange( 0.5, 2.5 );
		}
		
		wait d;
	}
	
	self walk();
}

/*
	watchPickupGun
*/
watchPickupGun()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( self usebuttonpressed() )
		{
			continue;
		}
		
		// todo have bots use turrets instead of just kicking them off of it
		if ( isdefined( self.turret ) )
		{
			self thread use( 0.5 );
			continue;
		}
		
		weap = self getcurrentweapon();
		
		if ( weap != "none" && self getammocount( weap ) )
		{
			// passing over a fresh body: sometimes take its gun (humans use ~6
			// weapons a session, bots 2)
			if ( self botWantsPickup() )
			{
				self thread use( 0.5 );
			}
			
			continue;
		}
		
		self thread use( 0.5 );
	}
}

/*
	True (35%, once per body) when standing on a recent death spot, away from
	the S&D bomb sites (use there would plant/defuse).
*/
botWantsPickup()
{
	if ( isdefined( self.bot.target ) || !isdefined( level.bot_fights ) || self.bot.isreloading )
	{
		return false;
	}
	
	if ( isdefined( self.isbombcarrier ) && self.isbombcarrier )
	{
		return false;
	}
	
	if ( isdefined( level.bombzones ) )
	{
		// gameobjects: no .origin, the position is curorigin / the trigger's
		for ( i = 0; i < level.bombzones.size; i++ )
		{
			zone = level.bombzones[ i ];
			pos = undefined;
			
			if ( isdefined( zone.curorigin ) )
			{
				pos = zone.curorigin;
			}
			else if ( isdefined( zone.trigger ) )
			{
				pos = zone.trigger.origin;
			}
			
			if ( isdefined( pos ) && distancesquared( self.origin, pos ) < 300 * 300 )
			{
				return false;
			}
		}
	}
	
	now = gettime();
	
	for ( i = 0; i < level.bot_fights.size; i++ )
	{
		spot = level.bot_fights[ i ];
		
		if ( now - spot.time > 90000 || distancesquared( self.origin, spot.origin ) > 70 * 70 )
		{
			continue;
		}
		
		if ( isdefined( self.bot.pickup_tried ) && self.bot.pickup_tried == spot.time )
		{
			return false;
		}
		
		self.bot.pickup_tried = spot.time;
		return randomint( 100 ) < 35;
	}
	
	return false;
}

/*
	Watches when the bot fires a grenade
*/
watchGrenadeFire()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill( "grenade_fire", nade, weapname );
		
		if ( !isdefined( nade ) )
		{
			continue;
		}
		
		if ( weapname == "c4_mp" )
		{
			self thread watchC4Thrown( nade );
		}
	}
}

/*
	Watches the c4
*/
watchC4Thrown( c4 )
{
	self endon( "disconnect" );
	c4 endon( "death" );
	
	wait 0.5;
	
	for ( ;; )
	{
		wait 1 + randomint( 50 ) * 0.05;
		
		shouldBreak = false;
		
		for ( i = 0; i < level.players.size; i++ )
		{
			player = level.players[ i ];
			
			if ( player == self )
			{
				continue;
			}
			
			if ( ( level.teambased && self.team == player.team ) || player.sessionstate != "playing" || !isalive( player ) )
			{
				continue;
			}
			
			if ( distancesquared( c4.origin, player.origin ) > 200 * 200 )
			{
				continue;
			}
			
			if ( !bullettracepassed( c4.origin, player.origin + ( 0, 0, 25 ), false, c4 ) )
			{
				continue;
			}
			
			shouldBreak = true;
		}
		
		if ( shouldBreak )
		{
			break;
		}
	}
	
	if ( self getcurrentweapon() != "c4_mp" )
	{
		self notify( "alt_detonate" );
	}
	else
	{
		self thread pressFire();
	}
}

/*
	Bot moves towards the point
*/
doBotMovement_loop( data )
{
	move_To = self.bot.moveto;
	angles = self getplayerangles();
	
	if ( gettime() < self.bot.juke_until && !isdefined( self.bot.target ) )
	{
		move_To = self.origin + anglestoforward( ( 0, self.bot.juke_yaw - 90, 0 ) ) * self.bot.juke_side * 100 + anglestoforward( ( 0, self.bot.juke_yaw, 0 ) ) * 60;
	}
	
	dir = ( 0, 0, 0 );
	
	// 24u dead zone (was 7u): stopping bots slid past their stop point and
	// stepped back, jittering in place (2.5x the humans' direction reversals).
	if ( distancesquared( self.origin, move_To ) >= 24 * 24 )
	{
		cosa = cos( 0 - angles[ 1 ] );
		sina = sin( 0 - angles[ 1 ] );
		
		// get the direction
		dir = move_To - self.origin;
		
		// rotate our direction according to our angles
		dir = ( dir[ 0 ] * cosa - dir[ 1 ] * sina,
				dir[ 0 ] * sina + dir[ 1 ] * cosa,
				0 );
				
		// make the length 127
		dir = vectornormalize( dir ) * 127;
		
		// invert the second component as the engine requires this
		dir = ( dir[ 0 ], 0 - dir[ 1 ], 0 );
	}
	
	// climb through windows
	if ( self ismantling() )
	{
		data.wasmantling = true;
		self crouch();
	}
	else if ( data.wasmantling )
	{
		data.wasmantling = false;
		self stand();
	}
	
	startPos = self.origin + ( 0, 0, 50 );
	startPosForward = startPos + anglestoforward( ( 0, angles[ 1 ], 0 ) ) * 25;
	bt = bullettrace( startPos, startPosForward, false, self );
	
	if ( bt[ "fraction" ] >= 1 )
	{
		// check if need to jump
		bt = bullettrace( startPosForward, startPosForward - ( 0, 0, 40 ), false, self );
		
		// only what's too high to step up (18u); curbs and stairs are walked
		if ( bt[ "fraction" ] < 1 && bt[ "normal" ][ 2 ] > 0.9 && bt[ "position" ][ 2 ] - self.origin[ 2 ] > 18 && data.i > 1.5 && !self isonladder() )
		{
			data.i = 0;
			self thread jump();
		}
	}
	// check if need to knife glass
	else if ( bt[ "surfacetype" ] == "glass" )
	{
		if ( data.i > 1.5 )
		{
			data.i = 0;
			self thread knife();
		}
	}
	else
	{
		// check if need to crouch
		if ( bullettracepassed( startPos - ( 0, 0, 25 ), startPosForward - ( 0, 0, 25 ), false, self ) && !self.bot.climbing )
		{
			self crouch();
		}
	}
	
	// move!
	if ( ( self.bot.wantsprint && self.bot.issprinting ) || isdefined( self.bot.knifing_target ) )
	{
		dir = ( 127, dir[ 1 ], 0 );
	}
	
	self BotBuiltinBotMovement( int( dir[ 0 ] ), int( dir[ 1 ] ) );
	self BotBuiltinBotMoveTo( move_To ); // cod4x
}

/*
	Bot moves towards the point
*/
doBotMovement()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	data = spawnstruct();
	data.wasmantling = false;
	
	for ( data.i = 0; true; data.i += 0.05 )
	{
		wait 0.05;
		
		waittillframeend;
		self doBotMovement_loop( data );
	}
}

/*
	Sets the factor of distance for a weapon
*/
SetWeaponDistMulti( weap )
{
	if ( weap == "none" )
	{
		return 1;
	}
	
	switch ( weaponclass( weap ) )
	{
		case "rifle":
			return 0.9;
			
		case "smg":
			return 0.7;
			
		case "pistol":
			return 0.5;
			
		default:
			return 1;
	}
}

/*
	Is the weap a sniper
*/
IsWeapSniper( weap )
{
	if ( weap == "none" )
	{
		return false;
	}
	
	if ( getweaponclass( weap ) != "weapon_sniper" )
	{
		return false;
	}
	
	return true;
}

/*
	The hold breath thread.
*/
watchHoldBreath()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 1;
		
		if ( self.bot.isfrozen )
		{
			continue;
		}
		
		self holdbreath( self playerads() > 0 );
	}
}

/*
	When the bot enters laststand, we fix the weapons
*/
onLastStand()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	while ( true )
	{
		while ( !self inLastStand() )
		{
			wait 0.05;
		}
		
		self notify( "kill_goal" );
		
		while ( self inLastStand() )
		{
			wait 0.05;
		}
	}
}

/*
	When the bot changes weapon.
*/
onWeaponChange()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	first = true;
	
	for ( ;; )
	{
		newWeapon = undefined;
		
		if ( first )
		{
			first = false;
			newWeapon = self getcurrentweapon();
			
			// hack fix for botstop overridding weapon
			if ( newWeapon != "none" )
			{
				self BotBuiltinBotWeapon( newWeapon );
				self switchtoweapon( newWeapon );
			}
		}
		else
		{
			self waittill( "weapon_change", newWeapon );
			
			// keep the bot's requested weapon in sync with pickups, grenade
			// returns etc.; otherwise it keeps asking for the old one and ends
			// up empty-handed
			if ( newWeapon != "none" )
			{
				self BotBuiltinBotWeapon( newWeapon );
			}
		}
		
		self.bot.is_cur_full_auto = WeaponIsFullAuto( newWeapon );
		self.bot.cur_weap_dist_multi = SetWeaponDistMulti( newWeapon );
		self.bot.is_cur_sniper = IsWeapSniper( newWeapon );
	}
}

/*
	Updates the bot if it is sprinting.
*/
sprint_watch()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill( "sprint_begin" );
		self.bot.issprinting = true;
		self waittill( "sprint_end" );
		self.bot.issprinting = false;
		self.bot.sprintendtime = gettime();
	}
}

/*
	Update's the bot if it is reloading.
*/
reload_watch_loop()
{
	self.bot.isreloading = true;
	
	while ( true )
	{
		ret = self waittill_any_timeout( 7.5, "reload" );
		
		if ( ret == "timeout" )
		{
			break;
		}
		
		weap = self getcurrentweapon();
		
		if ( weap == "none" )
		{
			break;
		}
		
		if ( self getweaponammoclip( weap ) >= weaponclipsize( weap ) )
		{
			break;
		}
	}
	
	self.bot.isreloading = false;
}

/*
	Update's the bot if it is reloading.
*/
reload_watch()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill( "reload_start" );
		
		self reload_watch_loop();
	}
}

/*
	Bots will update its needed stance according to the nodes on the level. Will also allow the bot to sprint when it can.
*/
stance_loop()
{
	self.bot.climbing = false;
	
	if ( self.bot.isfrozen )
	{
		return;
	}
	
	toStance = "stand";
	
	if ( self.bot.next_wp != -1 && self.bot.next_wp >= 0 && self.bot.next_wp < level.waypoints.size && isdefined( level.waypoints[ self.bot.next_wp ] ) )
	{
		toStance = level.waypoints[ self.bot.next_wp ].type;
	}
	
	if ( !isdefined( toStance ) )
	{
		toStance = "crouch";
	}
	
	// People don't crouch-walk while travelling; only some cautious approaches.
	if ( getdvarint( "bots_motor_model" ) )
	{
		if ( toStance == "stand" && isdefined( self.bot.motor_stance ) )
		{
			toStance = self.bot.motor_stance;
		}
	}
	else if ( toStance == "stand" && self.bot.cautious && randomint( 100 ) <= self.pers[ "bots" ][ "behavior" ][ "crouch" ] / 2 )
	{
		toStance = "crouch";
	}
	
	// a fight crouch holds while we move between waypoints (this used to stand
	// the bot back up: 0% of bot firing was crouched vs 22% of humans')
	if ( toStance == "stand" && self.bot.fight_crouch )
	{
		toStance = "crouch";
	}
	
	if ( toStance == "climb" )
	{
		self.bot.climbing = true;
		toStance = "stand";
	}
	
	if ( toStance != "stand" && toStance != "crouch" && toStance != "prone" )
	{
		toStance = "crouch";
	}
	
	if ( toStance == "stand" )
	{
		self stand();
	}
	else if ( toStance == "crouch" )
	{
		self crouch();
	}
	else
	{
		self prone();
	}
	
	curweap = self getcurrentweapon();
	time = gettime();
	chance = self.pers[ "bots" ][ "behavior" ][ "sprint" ];
	
	// human baseline sprints ~36% of the time; bots were at ~16%
	chance *= 1.6;
	
	if ( time - self.lastspawntime < 5000 )
	{
		chance *= 2;
	}
	
	if ( isdefined( self.bot.script_goal ) && distancesquared( self.origin, self.bot.script_goal ) > 256 * 256 )
	{
		chance *= 2;
	}
	
	if ( toStance != "stand" || self.bot.isreloading || self.bot.issprinting || self.bot.isfraggingafter || self.bot.issmokingafter )
	{
		return;
	}
	
	if ( self playerads() > 0.2 )
	{
		return;
	}
	
	if ( gettime() - self.bot.last_damage_time < 800 )
	{
		return;
	}
	
	if ( getdvarint( "bots_motor_model" ) )
	{
		// the motor model decides when to sprint (it starts sprints itself)
		return;
	}
	
	if ( randomint( 100 ) > chance )
	{
		return;
	}
	
	if ( isdefined( self.bot.target ) && self canFire( curweap ) && self isInRange( self.bot.target.dist, curweap ) )
	{
		return;
	}
	
	if ( self.bot.sprintendtime != -1 && time - self.bot.sprintendtime < 2000 )
	{
		return;
	}
	
	if ( !isdefined( self.bot.towards_goal ) || distancesquared( self.origin, physicstrace( self getEyePos(), self getEyePos() + anglestoforward( self getplayerangles() ) * 1024, false, undefined ) ) < level.bots_minsprintdistance || getConeDot( self.bot.towards_goal, self.origin, self getplayerangles() ) < 0.75 )
	{
		return;
	}
	
	self thread sprint();
	self thread setBotWantSprint();
}

/*
	Stops the sprint fix when goal is completed
*/
setBotWantSprint()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	self notify( "setBotWantSprint" );
	self endon( "setBotWantSprint" );
	
	self.bot.wantsprint = true;
	
	if ( randomint( 100 ) < 20 )
	{
		self thread sprintHop();
	}
	
	self waittill_notify_or_timeout( "kill_goal", 10 );
	
	self.bot.wantsprint = false;
}

/*
	Occasional sprint hop down a lane, like players bouncing off spawn.
*/
sprintHop()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon ( "game_ended" );
	
	wait randomfloatrange( 0.5, 1.2 );
	
	if ( !self.bot.wantsprint || !self.bot.issprinting )
	{
		return;
	}
	
	// (a jump at every sprint start was a bot tell; the motor model's
	// occasional hop covers human sprint jumps)
}

/*
	Bots will update its needed stance according to the nodes on the level. Will also allow the bot to sprint when it can.
*/
stance()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill_either( "finished_static_waypoints", "new_static_waypoint" );
		
		self stance_loop();
	}
}

/*
	Bot will wait until there is a grenade nearby and possibly throw it back.
*/
grenade_danger()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill( "grenade danger", grenade, attacker, weapname );
		
		if ( !isdefined( grenade ) )
		{
			continue;
		}
		
		if ( !getdvarint( "bots_play_nade" ) )
		{
			continue;
		}
		
		if ( weapname != "frag_grenade_mp" )
		{
			continue;
		}
		
		if ( isdefined( attacker ) && level.teambased && attacker.team == self.team )
		{
			continue;
		}
		
		self thread watch_grenade( grenade );
	}
}

/*
	Bot will throw back the given grenade if it is close, will watch until it is deleted or close.
*/
watch_grenade( grenade )
{
	self endon( "disconnect" );
	self endon( "death" );
	grenade endon( "death" );
	
	while ( 1 )
	{
		wait 1;
		
		if ( !isdefined( grenade ) )
		{
			return;
		}
		
		if ( self.bot.isfrozen )
		{
			continue;
		}
		
		if ( !bullettracepassed( self getEyePos(), grenade.origin, false, grenade ) )
		{
			continue;
		}
		
		if ( distancesquared( self.origin, grenade.origin ) > 20000 )
		{
			continue;
		}
		
		if ( self.bot.isfraggingafter || self.bot.issmokingafter )
		{
			continue;
		}
		
		self BotNotifyBotEvent( "throwback", "stop", grenade );
		self thread frag();
	}
}

/*
	Bot will wait until firing.
*/
check_reload()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill_notify_or_timeout( "weapon_fired", 5 );
		self thread reload_thread();
		self botMaybePistolSwap();
	}
}

/*
	Mag ran dry mid-fight at close range: often pull the pistol instead of
	reloading (humans swap after 8% of bursts; bots never did).
*/
botMaybePistolSwap()
{
	if ( !isdefined( self.bot.target ) || self.bot.pistol_swap || !isdefined( self.bot.target.dist ) )
	{
		return;
	}
	
	cur = self getcurrentweapon();
	
	if ( cur == "none" || getweaponclass( cur ) == "weapon_pistol" || self getweaponammoclip( cur ) > 0 )
	{
		return;
	}
	
	if ( self.bot.target.dist > 1200 || randomint( 100 ) >= 55 )
	{
		return;
	}
	
	list = self getweaponslist();
	
	for ( i = 0; i < list.size; i++ )
	{
		if ( getweaponclass( list[ i ] ) == "weapon_pistol" && self getammocount( list[ i ] ) )
		{
			self thread botPistolSwap( cur, list[ i ] );
			return;
		}
	}
}

/*
	Fights on with the pistol, then goes back to the primary a bit after.
*/
botPistolSwap( primary, pistol )
{
	self endon( "disconnect" );
	self endon( "death" );
	
	self.bot.pistol_swap = true;
	self maps\mp\bots\_bot_script::changeToWeapon( pistol );
	
	while ( isdefined( self.bot.target ) )
	{
		wait 0.25;
	}
	
	wait randomfloatrange( 1.0, 3.0 );
	
	if ( !isdefined( self.bot.target ) && self hasweapon( primary ) && self getcurrentweapon() == pistol )
	{
		self maps\mp\bots\_bot_script::changeToWeapon( primary );
	}
	
	self.bot.pistol_swap = false;
}

/*
	Bot will reload after firing if needed.
*/
reload_thread()
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "weapon_fired" );
	
	wait 2.5;
	
	if ( isdefined( self.bot.target ) || self.bot.isreloading || self.bot.isfraggingafter || self.bot.issmokingafter || self.bot.isfrozen )
	{
		// Low-skill panic reloads mid-fight, like real bad players.
		if ( !isdefined( self.bot.target ) || !isdefined( self.pers[ "bots" ][ "skill" ][ "base" ] ) || self.pers[ "bots" ][ "skill" ][ "base" ] > 2 || randomint( 100 ) >= 8 )
		{
			return;
		}
	}
	
	cur = self getcurrentweapon();
	
	if ( cur == "" || cur == "none" )
	{
		return;
	}
	
	if ( isweaponcliponly( cur ) || !self getweaponammostock( cur ) )
	{
		return;
	}
	
	maxsize = weaponclipsize( cur );
	cursize = self getweaponammoclip( cur );
	
	if ( cursize / maxsize < 0.5 )
	{
		self thread reload();
	}
}

/*
	Updates the bot's target bone
*/
updateBones()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		oldbones = self.pers[ "bots" ][ "skill" ][ "bones" ];
		bones = strtok( oldbones, "," );
		
		while ( oldbones == self.pers[ "bots" ][ "skill" ][ "bones" ] )
		{
			self waittill_notify_or_timeout( "new_enemy", self.pers[ "bots" ][ "skill" ][ "bone_update_interval" ] );
			
			if ( !isdefined( self.bot.target ) )
			{
				continue;
			}

			if ( bones.size <= 0 )
			{
				continue;
			}

			bone = random( bones );

			// The skill's bone list sets the weighting. Humans rarely go for the
			// head at long range, so drift those picks to center mass when allowed.
			if ( bone == "j_head" && isdefined( self.bot.target.dist ) && self.bot.target.dist > 1500 * 1500 && issubstr( oldbones, "j_spineupper" ) && randomint( 100 ) < 60 )
			{
				bone = "j_spineupper";
			}

			self.bot.target.bone = bone;
		}
	}
}

/*
	Creates the base target obj
*/
createTargetObj( ent, theTime )
{
	obj = spawnstruct();
	obj.entity = ent;
	obj.last_seen_pos = ( 0, 0, 0 );
	obj.last_vel = ( 0, 0, 0 );
	obj.dist = 0;
	obj.time = theTime;
	obj.trace_time = 0;
	obj.no_trace_time = 0;
	obj.trace_time_time = 0;
	obj.rand = randomint( 100 );
	obj.didlook = false;
	obj.offset = undefined;
	obj.bone = undefined;
	obj.aim_offset = undefined;
	obj.aim_offset_base = undefined;
	obj.react_required = -1;
	obj.confirm_count = 0;
	obj.danger = 0;
	
	// Whether this engagement would be settled with the knife at point blank
	// even with a loaded gun (most people just shoot; rushers knife more).
	knifeChance = 30;
	
	if ( isdefined( self.pers[ "bots" ][ "persona" ] ) && self.pers[ "bots" ][ "persona" ] == "rusher" )
	{
		knifeChance = 55;
	}
	
	obj.knife_pref = randomint( 100 ) < knifeChance;
	
	return obj;
}

/*
	Updates the target object's difficulty missing aim, inaccurate shots
*/
updateAimOffset( obj )
{
	if ( !isdefined( obj.aim_offset_base ) )
	{
		diffAimAmount = self.pers[ "bots" ][ "skill" ][ "aim_offset_amount" ];

		// Weapon-aware error: snipers precise when still, SMGs/shotguns spray wide while moving.
		errScale = 1.0;
		if ( self.bot.is_cur_sniper && self.bot.issprinting )
		{
			errScale = 2.0;
		}
		else if ( !self.bot.is_cur_full_auto )
		{
			errScale = 0.8;
		}

		if ( lengthsquared( self getvelocity() ) > 100 * 100 )
		{
			errScale *= 1.5;
		}
		
		if ( diffAimAmount > 0 )
		{
			obj.aim_offset_base = ( randomfloatrange( 0 - diffAimAmount * errScale, diffAimAmount * errScale ),
						randomfloatrange( 0 - diffAimAmount * errScale, diffAimAmount * errScale ),
						randomfloatrange( 0 - diffAimAmount * errScale, diffAimAmount * 0.7 ) );
		}
		else
		{
			obj.aim_offset_base = ( 0, 0, 0 );
		}
	}
	
	aimDiffTime = self.pers[ "bots" ][ "skill" ][ "aim_offset_time" ] * 1000;
	objCreatedFor = obj.trace_time;
	
	if ( objCreatedFor >= aimDiffTime )
	{
		offsetScalar = 0;
	}
	else
	{
		offsetScalar = 1 - objCreatedFor / aimDiffTime;
	}
	
	obj.aim_offset = obj.aim_offset_base * offsetScalar;
}

/*
	Computes contextual reaction time (ms) for a newly seen target.
	Base init_react_time is the mean; modifiers make it human:
	surprise (wide angle, long range, crouched still target) = slower,
	alert cues (muzzle flash, movement, damage from them, pre-aimed) = faster.
*/
getEffectiveReaction( ent, daDist, conedot, isScriptObj )
{
	base = self.pers[ "bots" ][ "skill" ][ "init_react_time" ];

	if ( isScriptObj )
	{
		return base;
	}

	react = base;

	// Surprise: far off-center targets take longer to notice.
	if ( conedot < 0.98 )
	{
		react += int( ( 0.98 - conedot ) * 1200 );
	}

	// Distance: humans spot close movement fast, far still targets slow.
	if ( daDist > 1500 * 1500 )
	{
		react += 150;
	}

	if ( daDist > 3000 * 3000 )
	{
		react += 250;
	}

	// Alert cues: firing or sprinting targets pop out (muzzle + sound + motion).
	if ( isdefined( ent.bots_firing ) && ent.bots_firing )
	{
		react -= 200;
	}

	if ( isplayer( ent ) )
	{
		evel = lengthsquared( ent getvelocity() );
		if ( evel > 120 * 120 )
		{
			react -= 120;
		}

		// Crouched still targets blend in.
		if ( evel < 20 * 20 && ent getstance() == "crouch" )
		{
			react += 150;
		}
	}

	// Self state: distracted while sprinting, reloading, or right after taking damage.
	if ( self.bot.issprinting )
	{
		react += 150;
	}

	if ( self.bot.isreloading )
	{
		react += 200;
	}

	if ( gettime() - self.bot.last_damage_time < 400 )
	{
		react += 120;
	}

	// Pre-aim bonus: already looking at the lane means much faster shot.
	if ( conedot > 0.995 )
	{
		react -= 120;
	}

	// Per-engagement jitter so reactions form a distribution, not a spike.
	react += randomintrange( 0 - 90, 90 );

	// Human floor: ~150ms when the target appears where we were already
	// looking (anticipation), ~180ms otherwise.
	reactFloor = 180;
	if ( conedot > 0.995 )
	{
		reactFloor = 150;
	}

	if ( react < reactFloor )
	{
		react = reactFloor;
	}

	return react;
}

/*
	Updates the target object to be traced Has LOS
*/
targetObjUpdateTraced( obj, daDist, ent, theTime, isScriptObj )
{
	distClose = self.pers[ "bots" ][ "skill" ][ "dist_start" ];
	distClose *= self.bot.cur_weap_dist_multi;
	distClose *= distClose;
	
	distMax = self.pers[ "bots" ][ "skill" ][ "dist_max" ];
	distMax *= self.bot.cur_weap_dist_multi;
	distMax *= distMax;
	
	timeMulti = 1;
	
	if ( !isScriptObj )
	{
		if ( daDist > distMax )
		{
			timeMulti = 0;
		}
		else if ( daDist > distClose )
		{
			timeMulti = 1 - ( ( daDist - distClose ) / ( distMax - distClose ) );
		}
	}
	
	obj.no_trace_time = 0;
	obj.trace_time += int( 50 * timeMulti );
	obj.dist = daDist;
	obj.last_seen_pos = ent.origin;
	obj.trace_time_time = theTime;
	obj.confirm_count += 1;

	if ( isplayer( ent ) )
	{
		obj.last_vel = ent getvelocity();

		// Danger score: who would a human prioritize?
		danger = 0;
		if ( isdefined( ent.bots_firing ) && ent.bots_firing )
		{
			danger += 3;
		}
		if ( daDist < 500 * 500 )
		{
			danger += 3;
		}
		else if ( daDist < 1000 * 1000 )
		{
			danger += 1;
		}
		if ( isdefined( self.bot.last_damage_attacker ) && self.bot.last_damage_attacker == ent && gettime() - self.bot.last_damage_time < 3000 )
		{
			danger += 2;
		}
		if ( isdefined( ent.isbombcarrier ) && ent.isbombcarrier )
		{
			danger += 1;
		}
		obj.danger = danger;
	}
	
	self updateAimOffset( obj );
}

/*
	Updates the target object to be not traced No LOS
*/
targetObjUpdateNoTrace( obj )
{
	obj.no_trace_time += 50;
	obj.trace_time = 0;
	obj.didlook = false;
	obj.confirm_count = 0;
	// last_seen_pos stays frozen: humans hold the angle where they lost you,
	// they don't track you through walls.
}

/*
	Returns true if myEye can see the bone of self
*/
checkTraceForBone( myEye, bone )
{
	boneLoc = self gettagorigin( bone );
	
	if ( !isdefined( boneLoc ) )
	{
		return false;
	}
	
	trace = bullettrace( myEye, boneLoc, false, undefined );
	
	return ( sighttracepassed( myEye, boneLoc, false, undefined ) && ( trace[ "fraction" ] >= 1.0 || trace[ "surfacetype" ] == "glass" ) );
}

/*
	The main target thread, will update the bot's main target. Will auto target enemy players and handle script targets.
*/
target_loop()
{
	myEye = self getEyePos();
	theTime = gettime();
	myAngles = self getplayerangles();
	myFov = self.pers[ "bots" ][ "skill" ][ "fov" ];
	bestTargets = [];
	bestTime = 2147483647;
	bestScore = 2147483647;
	rememberTime = self.pers[ "bots" ][ "skill" ][ "remember_time" ];
	initReactTime = self.pers[ "bots" ][ "skill" ][ "init_react_time" ];
	hasTarget = isdefined( self.bot.target );
	adsAmount = self playerads();
	adsFovFact = self.pers[ "bots" ][ "skill" ][ "ads_fov_multi" ];
	
	// reduce fov if ads'ing
	if ( adsAmount > 0 )
	{
		myFov *= 1 - adsFovFact * adsAmount;
	}
	
	if ( hasTarget && !isdefined( self.bot.target.entity ) )
	{
		self.bot.target = undefined;
		hasTarget = false;
	}
	
	playercount = level.players.size;
	
	for ( i = -1; i < playercount; i++ )
	{
		obj = undefined;
		
		if ( i == -1 )
		{
			if ( !isdefined( self.bot.script_target ) )
			{
				continue;
			}
			
			ent = self.bot.script_target;
			key = ent getentitynumber() + "";
			daDist = distancesquared( self.origin, ent.origin );
			obj = self.bot.targets[ key ];
			isObjDef = isdefined( obj );
			entOrigin = ent.origin;
			
			if ( isdefined( self.bot.script_target_offset ) )
			{
				entOrigin += self.bot.script_target_offset;
			}
			
			if ( SmokeTrace( myEye, entOrigin, level.smokeradius ) && bullettracepassed( myEye, entOrigin, false, ent ) )
			{
				if ( !isObjDef )
				{
					obj = self createTargetObj( ent, theTime );
					obj.offset = self.bot.script_target_offset;
					
					self.bot.targets[ key ] = obj;
				}
				
				self targetObjUpdateTraced( obj, daDist, ent, theTime, true );
			}
			else
			{
				if ( !isObjDef )
				{
					continue;
				}
				
				self targetObjUpdateNoTrace( obj );
				
				if ( obj.no_trace_time > rememberTime )
				{
					self.bot.targets[ key ] = undefined;
					continue;
				}
			}
		}
		else
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
			
			key = player getentitynumber() + "";
			obj = self.bot.targets[ key ];
			daDist = distancesquared( self.origin, player.origin );
			isObjDef = isdefined( obj );
			
			if ( ( level.teambased && self.team == player.team ) || player.sessionstate != "playing" || !isalive( player ) )
			{
				if ( isObjDef )
				{
					self.bot.targets[ key ] = undefined;
				}
				
				continue;
			}
			
			canTargetPlayer = ( ( player checkTraceForBone( myEye, "j_head" ) ||
						player checkTraceForBone( myEye, "j_ankle_le" ) ||
						player checkTraceForBone( myEye, "j_ankle_ri" ) )
						
					&& ( SmokeTrace( myEye, player.origin, level.smokeradius ) ||
						daDist < level.bots_maxknifedistance * 4 )
						
					 );

			rawCone = getConeDot( player.origin, self.origin, myAngles );
			effFov = myFov;
			if ( isdefined( player.bots_firing ) && player.bots_firing )
			{
				effFov -= self.pers[ "bots" ][ "skill" ][ "periph_bonus" ];
			}
			else if ( lengthsquared( player getvelocity() ) > 150 * 150 )
			{
				effFov -= self.pers[ "bots" ][ "skill" ][ "periph_bonus" ] * 0.7;
			}

			canTargetPlayer = canTargetPlayer && ( rawCone >= effFov || ( isObjDef && obj.trace_time ) );
						
			if ( isdefined( self.bot.target_this_frame ) && self.bot.target_this_frame == player )
			{
				self.bot.target_this_frame = undefined;
				
				canTargetPlayer = true;
			}
			
			if ( canTargetPlayer )
			{
				if ( !isObjDef )
				{
					obj = self createTargetObj( player, theTime );
					obj.react_required = self getEffectiveReaction( player, daDist, rawCone, false );
					
					self.bot.targets[ key ] = obj;
				}
				
				self targetObjUpdateTraced( obj, daDist, player, theTime, false );
			}
			else
			{
				if ( !isObjDef )
				{
					continue;
				}
				
				self targetObjUpdateNoTrace( obj );
				
				if ( obj.no_trace_time > rememberTime )
				{
					self.bot.targets[ key ] = undefined;
					continue;
				}
			}
		}
		
		if ( !isdefined( obj ) )
		{
			continue;
		}
		
		reactNeed = initReactTime;
		if ( isdefined( obj.react_required ) && obj.react_required >= 0 )
		{
			reactNeed = obj.react_required;
		}

		if ( theTime - obj.time < reactNeed )
		{
			continue;
		}

		// Trigger discipline: require 2 consecutive visible frames (100ms)
		// so edge flicker does not cause instant snaps. Knifing range exempt.
		minConfirm = 2;
		if ( isdefined( obj.dist ) && obj.dist < level.bots_maxknifedistance * 4 )
		{
			minConfirm = 1;
		}

		isCurTarget = hasTarget && isdefined( self.bot.target.entity ) && isdefined( obj.entity ) && obj.entity == self.bot.target.entity;

		if ( !isCurTarget && obj.confirm_count < minConfirm )
		{
			continue;
		}

		// Threat scoring: lower wins. Recency - danger bonus + distance penalty.
		// Humans prioritize shooters, close threats, and recent attackers.
		timeDiff = theTime - obj.trace_time_time;
		dangerBonus = 0;
		if ( isdefined( obj.danger ) )
		{
			dangerBonus = obj.danger * 700;
		}
		distPenalty = 0;
		if ( isdefined( obj.dist ) )
		{
			distPenalty = int( obj.dist / 500000 );
		}
		score = timeDiff - dangerBonus + distPenalty;

		// Stickiness: current target keeps a small advantage, prevents flicker.
		if ( hasTarget && isdefined( self.bot.target.entity ) && isdefined( obj.entity ) && obj.entity == self.bot.target.entity )
		{
			score -= 300;
		}

		if ( !isdefined( bestScore ) || score < bestScore )
		{
			bestTargets = [];
			bestScore = score;
			bestTime = timeDiff;
		}

		if ( score == bestScore )
		{
			bestTargets[ key ] = obj;
		}
	}
	
	if ( hasTarget && isdefined( self.bot.target ) && isdefined( self.bot.target.entity ) && isdefined( bestTargets[ self.bot.target.entity getentitynumber() + "" ] ) )
	{
		return;
	}
	
	bestDanger = -1;
	toBeTarget = undefined;

	bestKeys = getarraykeys( bestTargets );

	for ( i = bestKeys.size - 1; i >= 0; i-- )
	{
		cand = bestTargets[ bestKeys[ i ] ];
		candDanger = 0;
		if ( isdefined( cand.danger ) )
		{
			candDanger = cand.danger;
		}

		// Among tied scores prefer higher danger, then closer.
		if ( !isdefined( toBeTarget ) || candDanger > bestDanger || ( candDanger == bestDanger && cand.dist < toBeTarget.dist ) )
		{
			toBeTarget = cand;
			bestDanger = candDanger;
		}
	}
	
	beforeTargetID = -1;
	newTargetID = -1;
	
	if ( hasTarget && isdefined( self.bot.target.entity ) )
	{
		beforeTargetID = self.bot.target.entity getentitynumber();
	}
	
	if ( isdefined( toBeTarget ) && isdefined( toBeTarget.entity ) )
	{
		newTargetID = toBeTarget.entity getentitynumber();
	}
	
	if ( beforeTargetID != newTargetID )
	{
		switchPenalty = self.pers[ "bots" ][ "skill" ][ "switch_penalty" ];

		// Humans cannot snap-swap instantly. Enforce a small cost unless
		// the new target is obviously more dangerous or old target is lost.
		canSwitch = true;
		if ( hasTarget && isdefined( self.bot.target ) && theTime - self.bot.target_switch_time < switchPenalty )
		{
			oldDanger = 0;
			newDanger = 0;
			if ( isdefined( self.bot.target.danger ) )
			{
				oldDanger = self.bot.target.danger;
			}
			if ( isdefined( toBeTarget ) && isdefined( toBeTarget.danger ) )
			{
				newDanger = toBeTarget.danger;
			}
			oldLost = isdefined( self.bot.target.no_trace_time ) && self.bot.target.no_trace_time > 0;

			if ( !oldLost && newDanger < oldDanger + 3 )
			{
				canSwitch = false;
			}
		}

		if ( canSwitch )
		{
			self.bot.target = toBeTarget;
			self.bot.target_switch_time = theTime;
			self.bot.aim_vel_seen = ( 0, 0, 0 );
			self notify( "new_enemy" );
		}
	}
}

/*
	The main target thread, will update the bot's main target. Will auto target enemy players and handle script targets.
*/
target()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 0.05;
		
		if ( self maps\mp\_flashgrenades::isflashbanged() )
		{
			continue;
		}
		
		self target_loop();
	}
}

/*
	When the bot gets a new enemy.
*/
onNewEnemy()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		self waittill( "new_enemy" );
		
		if ( !isdefined( self.bot.target ) )
		{
			continue;
		}
		
		// humans crouch 18% of firing time and jump-shoot now and then
		roll = randomint( 100 );
		
		if ( roll < 25 && self getstance() == "stand" )
		{
			self thread botFightCrouch();
		}
		else if ( roll < 30 )
		{
			self thread jump();
		}
		
		if ( !isdefined( self.bot.target.entity ) || !isplayer( self.bot.target.entity ) )
		{
			continue;
		}
		
		if ( self.bot.target.didlook )
		{
			continue;
		}
		
		self thread watchToLook();
	}
}

/*
	Bots will jump or dropshot their enemy player.
*/
watchToLook()
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "new_enemy" );
	
	for ( ;; )
	{
		while ( isdefined( self.bot.target ) && self.bot.target.didlook )
		{
			wait 0.05;
		}
		
		while ( isdefined( self.bot.target ) && self.bot.target.no_trace_time )
		{
			wait 0.05;
		}
		
		if ( !isdefined( self.bot.target ) )
		{
			break;
		}
		
		self.bot.target.didlook = true;
		
		if ( self.bot.isfrozen )
		{
			continue;
		}
		
		if ( self.bot.target.dist > level.bots_maxshotgundistance * 2 )
		{
			continue;
		}
		
		if ( self.bot.target.dist <= level.bots_maxknifedistance )
		{
			continue;
		}
		
		if ( !self canFire( self getcurrentweapon() ) )
		{
			continue;
		}
		
		if ( !self isInRange( self.bot.target.dist, self getcurrentweapon() ) )
		{
			continue;
		}
		
		if ( self.bot.is_cur_sniper )
		{
			continue;
		}
		
		if ( randomint( 100 ) > self.pers[ "bots" ][ "behavior" ][ "jump" ] )
		{
			continue;
		}
		
		if ( !getdvarint( "bots_play_jumpdrop" ) )
		{
			continue;
		}
		
		if ( isdefined( self.bot.jump_time ) && gettime() - self.bot.jump_time <= 5000 )
		{
			continue;
		}
		
		if ( self.bot.target.rand <= self.pers[ "bots" ][ "behavior" ][ "strafe" ] )
		{
			if ( self getstance() != "stand" )
			{
				continue;
			}
			
			self.bot.jump_time = gettime();
			self jump();
		}
		else
		{
			if ( getConeDot( self.bot.target.last_seen_pos, self.origin, self getplayerangles() ) < 0.8 || self.bot.target.dist <= level.bots_noadsdistance )
			{
				continue;
			}
			
			self.bot.jump_time = gettime();
			self prone();
			self notify( "kill_goal" );
			wait 2.5;
			self crouch();
		}
	}
}

/*
	Assigns the bot's after target (bot will keep firing at a target after no sight or death)
*/
start_bot_after_target( who )
{
	self endon( "disconnect" );
	self endon( "death" );
	
	self.bot.after_target = who;
	self.bot.after_target_pos = who.origin;
	
	self notify( "kill_after_target" );
	self endon( "kill_after_target" );
	
	wait self.pers[ "bots" ][ "skill" ][ "shoot_after_time" ];
	
	self.bot.after_target = undefined;
}

/*
	Clears the bot's after target
*/
clear_bot_after_target()
{
	self.bot.after_target = undefined;
	self notify( "kill_after_target" );
}

/*
	This is the bot's main aimming thread. The bot will aim at its targets or a node its going towards. Bots will aim, fire, ads, grenade.
*/
aim_loop()
{
	aimspeed = self.pers[ "bots" ][ "skill" ][ "aim_time" ];
	
	if ( self IsStunned() || self isArtShocked() )
	{
		aimspeed = 1;
	}
	
	eyePos = self getEyePos();
	curweap = self getcurrentweapon();
	angles = self getplayerangles();
	adsAmount = self playerads();
	adsAimSpeedFact = self.pers[ "bots" ][ "skill" ][ "ads_aimspeed_multi" ];
	
	// reduce aimspeed if ads'ing
	if ( adsAmount > 0 )
	{
		aimspeed *= 1 + adsAimSpeedFact * adsAmount;
	}
	
	if ( isdefined( self.bot.target ) && isdefined( self.bot.target.entity ) && !( self.bot.prio_objective && isdefined( self.bot.script_aimpos ) ) )
	{
		no_trace_time = self.bot.target.no_trace_time;
		no_trace_look_time = self.pers[ "bots" ][ "skill" ][ "no_trace_look_time" ];
		
		if ( no_trace_time <= no_trace_look_time )
		{
			trace_time = self.bot.target.trace_time;
			last_pos = self.bot.target.last_seen_pos;
			target = self.bot.target.entity;
			conedot = 0;
			isplay = isplayer( self.bot.target.entity );
			
			offset = self.bot.target.offset;
			
			if ( !isdefined( offset ) )
			{
				offset = ( 0, 0, 0 );
			}
			
			aimoffset = self.bot.target.aim_offset;
			
			if ( !isdefined( aimoffset ) )
			{
				aimoffset = ( 0, 0, 0 );
			}
			
			dist = self.bot.target.dist;
			rand = self.bot.target.rand;
			no_trace_ads_time = self.pers[ "bots" ][ "skill" ][ "no_trace_ads_time" ];
			reaction_time = self.pers[ "bots" ][ "skill" ][ "reaction_time" ];
			nadeAimOffset = 0;
			
			bone = self.bot.target.bone;
			
			if ( !isdefined( bone ) )
			{
				bone = "j_spineupper";
			}
			
			if ( self.bot.isfraggingafter || self.bot.issmokingafter )
			{
				nadeAimOffset = dist / 3000;
			}
			else if ( curweap != "none" && weaponclass( curweap ) == "grenade" )
			{
				if ( getweaponclass( curweap ) == "weapon_projectile" )
				{
					nadeAimOffset = dist / 16000;
				}
				else
				{
					nadeAimOffset = dist / 3000;
				}
			}
			
			if ( no_trace_time && ( !isdefined( self.bot.after_target ) || self.bot.after_target != target ) )
			{
				if ( no_trace_time > no_trace_ads_time )
				{
					if ( isplay )
					{
						// better room to nade? cook time function with dist?
						if ( !self.bot.isfraggingafter && !self.bot.issmokingafter )
						{
							nade = self getValidGrenade();
							
							if ( isdefined( nade ) && rand <= self.pers[ "bots" ][ "behavior" ][ "nade" ] * 1.6 && bullettracepassed( eyePos, eyePos + ( 0, 0, 75 ), false, self ) && bullettracepassed( last_pos, last_pos + ( 0, 0, 100 ), false, target ) && dist > level.bots_mingrenadedistance && dist < level.bots_maxgrenadedistance && getdvarint( "bots_play_nade" ) )
							{
								if ( nade == "frag_grenade_mp" )
								{
									self thread frag( 2.5 );
								}
								else
								{
									self thread smoke( 0.5 );
								}
								
								self notify( "kill_goal" );
							}
						}
					}
				}
				else
				{
					if ( self canFire( curweap ) && self isInRange( dist, curweap ) && self canAds( dist, curweap ) )
					{
						if ( !self.bot.is_cur_sniper || !self.pers[ "bots" ][ "behavior" ][ "quickscope" ] )
						{
							self thread pressADS();
						}
					}
				}
				
				self.bot.look_src = "lastseen";
				self thread bot_lookat( last_pos + ( 0, 0, self getEyeHeight() + nadeAimOffset ), aimspeed );
				return;
			}
			
			if ( trace_time )
			{
				if ( isplay )
				{
					if ( !target IsPlayerModelOK() )
					{
						return;
					}
					
					aimpos = target gettagorigin( bone );
					
					if ( !isdefined( aimpos ) )
					{
						return;
					}
					
					aimpos += offset;
					aimpos += aimoffset;
					aimpos += ( 0, 0, nadeAimOffset );
					
					conedot = getConeDot( aimpos, eyePos, angles );
					
					if ( isdefined( self.bot.knifing_target ) && self.bot.knifing_target == target )
					{
						self thread bot_lookat( target gettagorigin( "j_spine4" ), 0.05 );
					}
					else if ( !nadeAimOffset && conedot > 0.999995 && lengthsquared( aimoffset ) < 0.05 )
					{
						self thread bot_lookat( aimpos, aimspeed );
					}
					else
					{
						self thread bot_lookat( aimpos, aimspeed, target getvelocity(), true );
					}
				}
				else
				{
					aimpos = target.origin;
					aimpos += offset;
					aimpos += aimoffset;
					aimpos += ( 0, 0, nadeAimOffset );
					
					conedot = getConeDot( aimpos, eyePos, angles );
					
					if ( !nadeAimOffset && conedot > 0.999995 && lengthsquared( aimoffset ) < 0.05 )
					{
						self thread bot_lookat( aimpos, aimspeed );
					}
					else
					{
						self thread bot_lookat( aimpos, aimspeed );
					}
				}
				
				wantKnife = self.bot.target.knife_pref || self.bot.isreloading || !self canFire( curweap );
				
				if ( isplay && wantKnife && !self.bot.isknifingafter && conedot > 0.9 && dist < level.bots_maxknifedistance && trace_time > reaction_time && getdvarint( "bots_play_knife" ) )
				{
					self clear_bot_after_target();
					self thread knife( target );
					return;
				}
				
				if ( !self canFire( curweap ) || !self isInRange( dist, curweap ) )
				{
					return;
				}
				
				canADS = ( self canAds( dist, curweap ) && conedot > 0.75 );
				
				if ( canADS )
				{
					stopAdsOverride = false;
					
					if ( self.bot.is_cur_sniper )
					{
						if ( self.pers[ "bots" ][ "behavior" ][ "quickscope" ] && self.bot.last_fire_time != -1 && gettime() - self.bot.last_fire_time < 1000 )
						{
							stopAdsOverride = true;
						}
						else
						{
							self notify( "kill_goal" );
						}
					}
					
					if ( !stopAdsOverride )
					{
						self thread pressADS();
					}
				}
				
				effReaction = reaction_time;
				if ( isdefined( self.pers[ "bots" ][ "skill" ][ "trigger_delay" ] ) )
				{
					effReaction += self.pers[ "bots" ][ "skill" ][ "trigger_delay" ];
				}
				// Moving targets: humans under-lead strafers, need extra settle time.
				if ( isplay && lengthsquared( target getvelocity() ) > 200 * 200 && dist > 1000 * 1000 )
				{
					effReaction += 120;
				}

				if ( trace_time > effReaction )
				{
					if ( ( !canADS || adsAmount >= 1.0 || self inLastStand() || self getstance() == "prone" ) && ( conedot > 0.985 || dist < level.bots_maxknifedistance ) && getdvarint( "bots_play_fire" ) )
					{
						self.bot.aim_fired_time = gettime();
						self botFire();
					}
					
					if ( isplay )
					{
						self thread start_bot_after_target( target );
					}
				}
				
				return;
			}
		}
	}
	
	if ( isdefined( self.bot.after_target ) )
	{
		nadeAimOffset = 0;
		last_pos = self.bot.after_target_pos;
		dist = distancesquared( self.origin, last_pos );
		
		if ( self.bot.isfraggingafter || self.bot.issmokingafter )
		{
			nadeAimOffset = dist / 3000;
		}
		else if ( curweap != "none" && weaponclass( curweap ) == "grenade" )
		{
			if ( getweaponclass( curweap ) == "weapon_projectile" )
			{
				nadeAimOffset = dist / 16000;
			}
			else
			{
				nadeAimOffset = dist / 3000;
			}
		}
		
		aimpos = last_pos + ( 0, 0, self getEyeHeight() + nadeAimOffset );
		conedot = getConeDot( aimpos, eyePos, angles );
		
		self.bot.look_src = "target";
		self thread bot_lookat( aimpos, aimspeed );
		
		if ( !self canFire( curweap ) || !self isInRange( dist, curweap ) )
		{
			return;
		}
		
		canADS = ( self canAds( dist, curweap ) && conedot > 0.75 );
		
		if ( canADS )
		{
			stopAdsOverride = false;
			
			if ( self.bot.is_cur_sniper )
			{
				if ( self.pers[ "bots" ][ "behavior" ][ "quickscope" ] && self.bot.last_fire_time != -1 && gettime() - self.bot.last_fire_time < 1000 )
				{
					stopAdsOverride = true;
				}
				else
				{
					self notify( "kill_goal" );
				}
			}
			
			if ( !stopAdsOverride )
			{
				self thread pressADS();
			}
		}
		
		if ( ( !canADS || adsAmount >= 1.0 || self inLastStand() || self getstance() == "prone" ) && ( conedot > 0.95 || dist < level.bots_maxknifedistance ) && getdvarint( "bots_play_fire" ) )
		{
			self.bot.aim_fired_time = gettime();
			self botFire();
		}
		
		return;
	}
	
	if ( self.bot.next_wp != -1 && self.bot.next_wp >= 0 && self.bot.next_wp < level.waypoints.size && isdefined( level.waypoints[ self.bot.next_wp ].angles ) )
	{
		forwardPos = anglestoforward( level.waypoints[ self.bot.next_wp ].angles ) * 1024;
		
		self.bot.look_src = "wpangles";
		self thread bot_lookat( eyePos + forwardPos, aimspeed );
	}
	else if ( isdefined( self.bot.script_aimpos ) )
	{
		self.bot.look_src = "scriptaim";
		self thread bot_lookat( self.bot.script_aimpos, aimspeed );
	}
	else
	{
		// moving: look down the part of the path we can see (the furthest
		// visible of the next two nodes), not through the wall at a corner.
		// Standing still: the path doesn't matter, watch something useful.
		lookat = undefined;
		moving = lengthsquared( self getvelocity() ) > 60 * 60;
		
		if ( moving && !self.bot.climbing )
		{
			nodes = [];
			nodes[ 0 ] = self.bot.second_next_wp;
			nodes[ 1 ] = self.bot.next_wp;
			
			for ( i = 0; i < nodes.size && !isdefined( lookat ); i++ )
			{
				if ( nodes[ i ] >= 0 && nodes[ i ] < level.waypoints.size && bullettracepassed( eyePos, level.waypoints[ nodes[ i ] ].origin + ( 0, 0, 50 ), false, self ) )
				{
					lookat = level.waypoints[ nodes[ i ] ].origin;
				}
			}
			
			if ( !isdefined( lookat ) )
			{
				lookat = self.origin + vectornormalize( self getvelocity() ) * 400; // where we're heading
			}
		}
		
		glance = self getIdleGlance();
		lookpos = undefined;
		
		if ( isdefined( glance ) )
		{
			self.bot.look_src = self.bot.glance_src;
			lookpos = glance;
		}
		else if ( isdefined( lookat ) )
		{
			self.bot.look_src = "path";
			lookpos = self botPathLookPoint( lookat );
		}
		
		// never stare into a wall: swap for something worth watching
		if ( !isdefined( lookpos ) || !self botLookIsUseful( lookpos ) )
		{
			lookpos = self botUsefulLook( moving );
			self.bot.look_src = "useful";
		}
		else
		{
			self.bot.useful_look_until = 0;
		}
		
		if ( isdefined( lookpos ) )
		{
			self thread bot_lookat( lookpos, aimspeed );
		}
		else
		{
			self.bot.look_src = "none";
		}
	}
}

/*
	Loads where humans looked from each spot of this map
	(scriptdata/gaze/<map>.txt, tools/gen_gaze_model.py) into level.bot_gaze,
	keyed "ix,iy,iz,ctx" (128u cells, 96u levels; ctx "s" still or "m0".."m7"
	moving heading sector). Entries stay unparsed until used.
*/
bot_gaze_load()
{
	level.bot_gaze = [];
	level.bot_gaze_count = 0;
	filename = "gaze/" + getdvar( "mapname" ) + ".txt";
	
	if ( !BotBuiltinFileExists( filename ) )
	{
		return;
	}
	
	f = BotBuiltinFileOpen( filename, "read" );
	
	if ( f < 1 )
	{
		return;
	}
	
	n = 0;
	
	for ( line = BotBuiltinReadLine( f ); isdefined( line ); line = BotBuiltinReadLine( f ) )
	{
		t = strtok( line, " " );
		
		if ( t.size < 5 )
		{
			continue;
		}
		
		key = t[ 0 ] + "," + t[ 1 ] + "," + t[ 2 ] + "," + t[ 3 ];
		rest = t[ 4 ];
		
		for ( k = 5; k < t.size; k++ )
		{
			rest += " " + t[ k ];
		}
		
		level.bot_gaze[ key ] = rest;
		n++;
		
		if ( n % 250 == 0 )
		{
			wait 0.05;
		}
	}
	
	BotBuiltinFileClose( f );
	level.bot_gaze_count = n;
	BotBuiltinPrintConsole( "Gaze: loaded " + n + " human look entries for " + getdvar( "mapname" ) );
}

/*
	Where to look, sampled from where real players looked from our cell (or
	a neighbouring one) in our situation: a view direction weighted by the
	time humans spent looking that way, held for about as long as people
	hold a look. Undefined when there is no data for here.
*/
botGazeLook()
{
	now = gettime();
	vel = self getvelocity();
	ctx = "s";
	
	if ( lengthsquared( vel ) > 60 * 60 )
	{
		h = vectortoangles( vel )[ 1 ];
		
		if ( h < 0 )
		{
			h += 360;
		}
		
		ctx = "m" + ( int( ( h + 22.5 ) / 45 ) % 8 );
	}
	else if ( lengthsquared( vel ) > 25 * 25 )
	{
		return undefined; // drifting: keep the current look
	}
	
	ix = navgen_round_int( self.origin[ 0 ] / 128 );
	iy = navgen_round_int( self.origin[ 1 ] / 128 );
	iz = navgen_round_int( self.origin[ 2 ] / 96 );
	data = level.bot_gaze[ ix + "," + iy + "," + iz + "," + ctx ];
	
	for ( r = 0; !isdefined( data ) && r < 8; r++ )
	{
		dx = 1 - ( r % 3 );
		dy = 1 - int( r / 3 );
		data = level.bot_gaze[ ( ix + dx ) + "," + ( iy + dy ) + "," + iz + "," + ctx ];
	}
	
	if ( !isdefined( data ) )
	{
		return undefined;
	}
	
	ents = strtok( data, ";" );
	roll = randomint( 100 );
	pick = ents[ 0 ];
	
	for ( i = 0; i < ents.size; i++ )
	{
		f = strtok( ents[ i ], " " );
		
		if ( roll < int( f[ 2 ] ) )
		{
			pick = ents[ i ];
			break;
		}
		
		roll -= int( f[ 2 ] );
	}
	
	f = strtok( pick, " " );
	yaw = float_old( f[ 0 ] ) + randomfloatrange( -8, 8 );
	pitch = float_old( f[ 1 ] ) + randomfloatrange( -3, 3 );
	
	self.bot.glance_pos = self getEyePos() + anglestoforward( ( pitch, yaw, 0 ) ) * 1000;
	self.bot.glance_src = "gaze";
	
	if ( ctx == "s" )
	{
		self.bot.glance_until = now + randomintrange( 1200, 3500 );
	}
	else
	{
		self.bot.glance_until = now + randomintrange( 500, 1400 );
	}
	
	return self.bot.glance_pos;
}

/*
	Rounds to the nearest integer.
*/
navgen_round_int( v )
{
	if ( v < 0 )
	{
		return 0 - int( 0.5 - v );
	}
	
	return int( v + 0.5 );
}

/*
	A look point is useful if the view toward it runs at least 200u (or
	reaches the point) before hitting something.
*/
botLookIsUseful( pos )
{
	eye = self getEyePos();
	d = distance( eye, pos );
	
	if ( d < 1 )
	{
		return false;
	}
	
	far = eye + vectornormalize( pos - eye ) * 200;
	
	if ( d < 200 )
	{
		far = pos;
	}
	
	return bullettracepassed( eye, far, false, self );
}

/*
	Something worth watching instead of a wall, kept for 1.5-3.5s so the
	view doesn't flick around: a likely enemy spot, else a spot a player
	could stand in sight, else the most open line of sight. Ahead of us
	(within 100 deg of our heading) while moving, anywhere when still.
*/
botUsefulLook( moving )
{
	now = gettime();
	
	if ( isdefined( self.bot.useful_look ) && isdefined( self.bot.useful_look_until ) && now < self.bot.useful_look_until )
	{
		return self.bot.useful_look;
	}
	
	yaw = self getplayerangles()[ 1 ];
	maxOff = 180;
	
	if ( moving )
	{
		yaw = vectortoangles( self getvelocity() )[ 1 ];
		maxOff = 100;
	}
	
	pos = self botLikelyEnemySpot( yaw, maxOff );
	
	if ( !isdefined( pos ) )
	{
		pos = self botVisiblePlayerSpot( yaw, maxOff );
	}
	
	if ( !isdefined( pos ) )
	{
		// most open line of sight at eye level
		eye = self getEyePos();
		best = -1;
		
		for ( i = 0; i < 8; i++ )
		{
			dir = anglestoforward( ( 0, yaw + randomfloatrange( 0 - maxOff, maxOff ), 0 ) );
			bt = bullettrace( eye, eye + dir * 1500, false, self );
			d = distancesquared( eye, bt[ "position" ] );
			
			if ( d > best )
			{
				best = d;
				pos = bt[ "position" ];
			}
		}
	}
	
	self.bot.useful_look = pos;
	self.bot.useful_look_until = now + randomintrange( 1500, 3500 );
	return pos;
}

/*
	A spot someone could be standing that we can see: a random walkable
	node 300-2500u away, within maxOff degrees of yaw, in line of sight at
	chest height. Undefined if none found in a few tries.
*/
botVisiblePlayerSpot( yaw, maxOff )
{
	if ( !level.waypoints.size )
	{
		return undefined;
	}
	
	eye = self getEyePos();
	
	for ( tries = 0; tries < 12; tries++ )
	{
		spot = level.waypoints[ randomint( level.waypoints.size ) ].origin + ( 0, 0, 48 );
		d = distancesquared( eye, spot );
		
		if ( d < 300 * 300 || d > 2500 * 2500 )
		{
			continue;
		}
		
		off = angleclamp180( vectortoangles( spot - eye )[ 1 ] - yaw );
		
		if ( off > maxOff || off < 0 - maxOff )
		{
			continue;
		}
		
		if ( bullettracepassed( eye, spot, false, self ) )
		{
			return spot;
		}
	}
	
	return undefined;
}

/*
	Where to look while walking a path toward pos (a floor point): far down
	the path at about eye level, like people do, not at the floor of a
	waypoint a few steps ahead. Pitch follows the path's slope (stairs) but
	stays within 15 degrees.
*/
botPathLookPoint( pos )
{
	eye = self getEyePos();
	target = pos + ( 0, 0, self getEyeHeight() );
	flat = ( target[ 0 ] - eye[ 0 ], target[ 1 ] - eye[ 1 ], 0 );
	h = distance( ( 0, 0, 0 ), flat );
	
	if ( h < 1 )
	{
		return eye + anglestoforward( ( 0, self getplayerangles()[ 1 ], 0 ) ) * 800;
	}
	
	slope = ( target[ 2 ] - eye[ 2 ] ) / h;
	
	if ( slope > 0.27 ) // tan 15
	{
		slope = 0.27;
	}
	else if ( slope < -0.27 )
	{
		slope = -0.27;
	}
	
	return eye + vectornormalize( flat ) * 800 + ( 0, 0, slope * 800 );
}

/*
	Human movement rhythm, learned from demos (_bot_motor_data.gsc): outside of
	fights and objective actions, cycle through sprint / run / ads_walk /
	crouch_walk / still_stand / still_crouch / prone with the real dwell times
	and transition odds of the matching mode (sd or respawn).
*/
motorController()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	
	profile = "respawn";
	
	if ( level.gametype == "sd" )
	{
		profile = "sd";
	}
	
	self.bot.motor_state = "run";
	self.bot.motor_stance = undefined;
	self.bot.motor_pause_until = 0;
	
	for ( ;; )
	{
		if ( !getdvarint( "bots_motor_model" ) || !self motorActive() )
		{
			self motorRelease();
			self.bot.motor_state = "run";
			wait 0.25;
			continue;
		}
		
		cur = self.bot.motor_state;
		
		// people stop at corners and cover, not in the middle of open ground
		if ( ( cur == "still_stand" || cur == "still_crouch" || cur == "prone" ) && !self botNearCover() )
		{
			cur = "run";
			self.bot.motor_state = cur;
		}
		
		dwell = self motorDwell( profile, cur );
		self motorApply( cur, dwell );
		
		// stop early when a fight starts; combat owns movement then
		for ( t = 0; t < dwell && self motorActive(); t += 0.05 )
		{
			moving = lengthsquared( self getvelocity() ) > 100 * 100;
			
			// sprints start once we're actually moving along the path
			if ( cur == "sprint" && moving && !self.bot.issprinting && !self.bot.isreloading )
			{
				self thread sprint();
				self thread setBotWantSprint();
			}
			
			// occasional hop while running (~1.4/min; humans jump ~3.7/min in
			// all, the rest over obstacles and in fights)
			if ( ( cur == "sprint" || cur == "run" ) && moving && randomint( 1000 ) < 6 )
			{
				self thread jump();
			}
			
			// occasional juke: a quick sidestep while running (humans ~1 sharp
			// direction change a minute, bots none)
			if ( ( cur == "sprint" || cur == "run" ) && moving && randomint( 1000 ) < 3 )
			{
				self botStartJuke();
			}
			
			wait 0.05;
		}
		
		self motorRelease();
		self.bot.motor_state = self botMotorContext( self motorNext( profile, cur ) );
	}
}

/*
	Starts a 0.25-0.5s sidestep off the travel direction if there is room and
	floor on that side; doBotMovement_loop steers it.
*/
botStartJuke()
{
	yaw = vectortoangles( self getvelocity() )[ 1 ];
	start = self.origin + ( 0, 0, 30 );
	side = 1;
	
	if ( randomint( 2 ) )
	{
		side = -1;
	}
	
	for ( i = 0; i < 2; i++ )
	{
		end = start + anglestoforward( ( 0, yaw - 90, 0 ) ) * side * 110; // right of travel
		
		if ( bullettracepassed( start, end, false, self ) && !bullettracepassed( end, end - ( 0, 0, 80 ), false, self ) )
		{
			self.bot.juke_yaw = yaw;
			self.bot.juke_side = side;
			self.bot.juke_until = gettime() + randomintrange( 250, 500 );
			return;
		}
		
		side = 0 - side;
	}
}

/*
	True next to cover (a wall within 80u to the side, behind or ahead) or at a
	path corner (next waypoint within 64u).
*/
botNearCover()
{
	if ( self.bot.next_wp != -1 && self.bot.next_wp >= 0 && self.bot.next_wp < level.waypoints.size && distancesquared( self.origin, level.waypoints[ self.bot.next_wp ].origin ) < 64 * 64 )
	{
		return true;
	}
	
	start = self.origin + ( 0, 0, 40 );
	angles = self getplayerangles();
	yaw = angles[ 1 ];
	
	for ( i = 0; i < 4; i++ )
	{
		if ( !bullettracepassed( start, start + anglestoforward( ( 0, yaw + i * 90, 0 ) ) * 80, false, self ) )
		{
			return true;
		}
	}
	
	return false;
}

/*
	Context bias on the next motor state (human demo lifts): under threat
	(heard shots / recent fight nearby) people ADS and crouch more and sprint
	less; when calm they sprint freely.
*/
botMotorContext( next )
{
	threat = isdefined( self bot_recent_shot( 3000, 2000 ) ) || isdefined( bot_pick_fight_spot_near( self.origin, 1200 ) );
	
	if ( threat )
	{
		if ( ( next == "run" || next == "sprint" ) && randomint( 100 ) < 35 )
		{
			return "ads_walk";
		}
		
		if ( next == "still_stand" && randomint( 100 ) < 30 )
		{
			return "still_crouch";
		}
	}
	else if ( next == "run" && randomint( 100 ) < 45 )
	{
		// demos: bots sprinted 12% of the time vs humans 24%
		return "sprint";
	}
	
	return next;
}

/*
	A teammate went down nearby: freeze, maybe crouch, and look toward where
	the shots came from (with error; the killfeed and sound give a rough idea).
*/
botMateDown( deathPos, threatPos )
{
	self endon( "disconnect" );
	self endon( "death" );
	
	wait randomfloatrange( 0.2, 0.5 );
	
	if ( isdefined( self.bot.target ) || randomint( 100 ) >= 75 )
	{
		return;
	}
	
	look = deathPos;
	
	if ( isdefined( threatPos ) )
	{
		err = distance( self.origin, threatPos ) * 0.2;
		look = threatPos + ( randomfloatrange( 0 - err, err ), randomfloatrange( 0 - err, err ), 0 );
	}
	
	dur = randomfloatrange( 1.2, 3.0 );
	self BotTelemetryEvent( "mate_down" );
	self.bot.motor_pause_until = gettime() + int( dur * 1000 );
	self.bot.glance_pos = look + ( 0, 0, 50 );
	self.bot.glance_until = gettime() + int( dur * 1000 );
	self.bot.glance_next = self.bot.glance_until;
	
	if ( randomint( 100 ) < 35 && self getstance() == "stand" )
	{
		self crouch();
		wait dur;
		
		if ( !isdefined( self.bot.target ) )
		{
			self stand();
		}
	}
}

/*
	The motor model runs when not fighting, climbing or doing an objective action.
*/
motorActive()
{
	if ( isdefined( self.bot.target ) || self.bot.climbing || self.bot.isfrozen )
	{
		return false;
	}
	
	if ( self isDefusing() || self isPlanting() || self inLastStand() )
	{
		return false;
	}
	
	return true;
}

/*
	True while a motor stop state holds the bot in place.
*/
motorPaused()
{
	return getdvarint( "bots_motor_model" ) && gettime() < self.bot.motor_pause_until && !isdefined( self.bot.target );
}

/*
	Starts a motor state.
*/
motorApply( state, dwell )
{
	self.bot.motor_stance = undefined;
	
	switch ( state )
	{
		case "ads_walk":
			self thread pressADS( dwell );
			break;
			
		case "crouch_walk":
			self.bot.motor_stance = "crouch";
			self crouch();
			break;
			
		case "still_stand":
			self.bot.motor_pause_until = gettime() + int( dwell * 1000 );
			break;
			
		case "still_crouch":
			self.bot.motor_stance = "crouch";
			self crouch();
			self.bot.motor_pause_until = gettime() + int( dwell * 1000 );
			break;
			
		case "prone":
			self.bot.motor_stance = "prone";
			self prone();
			self.bot.motor_pause_until = gettime() + int( dwell * 1000 );
			break;
	}
}

/*
	Ends the current motor state's effects.
*/
motorRelease()
{
	self.bot.motor_pause_until = 0;
	
	if ( isdefined( self.bot.motor_stance ) )
	{
		self.bot.motor_stance = undefined;
		self stand();
	}
}

/*
	Drops to a knee for the fight, stands back up when it's over.
*/
botFightCrouch()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	wait randomfloatrange( 0.1, 0.4 );
	self.bot.fight_crouch = true;
	self crouch();
	
	while ( isdefined( self.bot.target ) )
	{
		wait 0.25;
	}
	
	wait randomfloatrange( 0.3, 1.0 );
	self.bot.fight_crouch = false;
	self stand();
}

/*
	Uniform pick from a comma list of values, jittered +-15% (empirical sampling).
*/
botSampleList( list )
{
	v = strtok( list, "," );
	return float_old( v[ randomint( v.size ) ] ) * randomfloatrange( 0.85, 1.15 );
}

/*
	Samples a dwell time (s) from the human decile table: pick a decile band and
	interpolate inside it; the top band stretches out to cover the long tail.
*/
motorDwell( profile, state )
{
	data = maps\mp\bots\_bot_motor_data::motor_data( profile + "_" + state + "_dwell" );
	
	if ( !isdefined( data ) )
	{
		return 0.5;
	}
	
	d = strtok( data, "," );
	i = randomint( d.size + 1 );
	
	if ( i == 0 )
	{
		lo = float_old( d[ 0 ] ) * 0.5;
		hi = float_old( d[ 0 ] );
	}
	else if ( i == d.size )
	{
		lo = float_old( d[ d.size - 1 ] );
		hi = lo * 2.5;
	}
	else
	{
		lo = float_old( d[ i - 1 ] );
		hi = float_old( d[ i ] );
	}
	
	v = randomfloatrange( lo, hi + 0.01 );
	
	if ( v < 0.1 )
	{
		v = 0.1;
	}
	
	return v;
}

/*
	Next motor state from the human transition weights.
*/
motorNext( profile, state )
{
	data = maps\mp\bots\_bot_motor_data::motor_data( profile + "_" + state + "_next" );
	
	if ( !isdefined( data ) )
	{
		return "run";
	}
	
	// where and when: how much more/less humans use each state in this map
	// area and at this time into the round (demos: bots' states fit the place
	// far worse than humans', -0.9 vs +0.1 log-lift)
	areaLift = undefined;
	phaseLift = undefined;
	
	if ( profile == "sd" )
	{
		areaLift = maps\mp\bots\_bot_motor_data::motor_data( "sd_area_" + getdvar( "mapname" ) + "_" + navgen_round_int( self.origin[ 0 ] / 512 ) + "_" + navgen_round_int( self.origin[ 1 ] / 512 ) );
		phaseLift = maps\mp\bots\_bot_motor_data::motor_data( "sd_phase_" + motorPhaseBin( ( gettime() - self.bot.spawn_time ) / 1000 ) );
	}
	
	entries = strtok( data, "," );
	names = [];
	weights = [];
	total = 0;
	
	for ( i = 0; i < entries.size; i++ )
	{
		parts = strtok( entries[ i ], ":" );
		names[ i ] = parts[ 0 ];
		weights[ i ] = int( parts[ 1 ] ) * motorLift( areaLift, parts[ 0 ] ) * motorLift( phaseLift, parts[ 0 ] );
		total += weights[ i ];
	}
	
	roll = randomfloat( total );
	
	for ( i = 0; i < entries.size; i++ )
	{
		if ( roll < weights[ i ] )
		{
			return names[ i ];
		}
		
		roll -= weights[ i ];
	}
	
	return "run";
}

/*
	Lift (1.0 = human base rate) of a state in a "state:x100,..." list.
*/
motorLift( list, state )
{
	if ( !isdefined( list ) )
	{
		return 1.0;
	}
	
	entries = strtok( list, "," );
	
	for ( i = 0; i < entries.size; i++ )
	{
		parts = strtok( entries[ i ], ":" );
		
		if ( parts[ 0 ] == state )
		{
			return int( parts[ 1 ] ) / 100.0;
		}
	}
	
	return 1.0;
}

/*
	Round phase bin for the motor lifts (tools/gen_motor_model.py PHASES).
*/
motorPhaseBin( sec )
{
	if ( sec <= 5 )
	{
		return 0;
	}
	
	if ( sec <= 15 )
	{
		return 1;
	}
	
	if ( sec <= 30 )
	{
		return 2;
	}
	
	if ( sec <= 60 )
	{
		return 3;
	}
	
	if ( sec <= 120 )
	{
		return 4;
	}
	
	return 5;
}

/*
	% chance to hold after reaching a roam goal: mode profile, then persona
	(campers hold nearly always, mobile players less).
*/
botHoldChance()
{
	chance = bot_mode_value( "hold_chance" );
	persona = self.pers[ "bots" ][ "persona" ];
	
	if ( isdefined( persona ) && persona == "anchor" )
	{
		chance += 30;
	}
	else if ( isdefined( persona ) && persona == "rusher" )
	{
		chance *= 0.6;
	}
	
	return chance;
}

/*
	Stop and hold an angle: face the most useful lane (where fighting was, else
	the longest open sightline), crouch/prone/ADS per mode, and wait until the
	time is up or an enemy shows up.
*/
botHoldPosition()
{
	minMs = bot_mode_value( "hold_min_ms" );
	maxMs = bot_mode_value( "hold_max_ms" );
	prone = bot_mode_value( "hold_prone" );
	persona = self.pers[ "bots" ][ "persona" ];
	
	if ( isdefined( persona ) && persona == "anchor" )
	{
		maxMs *= 2.5;
		prone += 25;
	}
	else if ( isdefined( persona ) && persona == "rusher" )
	{
		minMs *= 0.6;
		maxMs *= 0.6;
	}
	
	dur = randomintrange( int( minMs ), int( maxMs ) ) / 1000;
	
	lane = undefined;
	
	if ( randomint( 100 ) < 50 )
	{
		spot = self bot_pick_fight_spot( 300, 3000 );
		
		if ( isdefined( spot ) && bullettracepassed( self getEyePos(), spot + ( 0, 0, 40 ), false, self ) )
		{
			lane = spot + ( 0, 0, 40 );
		}
	}
	
	if ( !isdefined( lane ) )
	{
		lane = self botOpenLane();
	}
	
	self.bot.glance_pos = lane;
	self.bot.glance_until = gettime() + int( dur * 1000 );
	self.bot.glance_next = self.bot.glance_until;
	
	roll = randomint( 100 );
	
	if ( roll < prone )
	{
		self prone();
	}
	else if ( roll < prone + bot_mode_value( "hold_crouch" ) )
	{
		self crouch();
	}
	
	// ADS only when watching a real sightline, where someone could appear
	if ( distancesquared( self getEyePos(), lane ) > 700 * 700 && randomint( 100 ) < bot_mode_value( "hold_ads" ) )
	{
		self thread pressADS( dur );
	}
	
	self botSetMoveTo( self.origin );
	self BotTelemetryEvent( "hold" );
	self waittill_notify_or_timeout( "new_enemy", dur );
	self stand();
}

/*
	True if the view is not blocked within dist units (not staring at a wall).
*/
botViewIsOpen( dist )
{
	eye = self getEyePos();
	return bullettracepassed( eye, eye + anglestoforward( self getplayerangles() ) * dist, false, self );
}

/*
	The farthest open sightline from here (6 random directions).
*/
botOpenLane()
{
	eye = self getEyePos();
	best = -1;
	lane = eye + anglestoforward( self getplayerangles() ) * 500;
	
	for ( i = 0; i < 6; i++ )
	{
		trace = bullettrace( eye, eye + anglestoforward( ( 0, randomint( 360 ), 0 ) ) * 3000, false, self );
		d = distancesquared( eye, trace[ "position" ] );
		
		if ( d > best )
		{
			best = d;
			lane = trace[ "position" ];
		}
	}
	
	return lane;
}

/*
	Where to roam when there is no objective/script goal. People head toward
	the fighting (stopping short to take a look), otherwise patrol nearby lanes
	and only sometimes rotate across the map.
*/
pickRoamGoal()
{
	// heard a fight: many players go toward it (humans are near enemies 39% of
	// the time vs our bots' 16%); stop short and approach
	shot = self bot_recent_shot( 5000, 2500 );
	
	if ( isdefined( shot ) )
	{
		chance = 45;
		persona = self.pers[ "bots" ][ "persona" ];
		
		if ( isdefined( persona ) && persona == "rusher" )
		{
			chance = 70;
		}
		else if ( isdefined( persona ) && persona == "anchor" )
		{
			chance = 15;
		}
		
		if ( randomint( 100 ) < chance && distancesquared( self.origin, shot ) > 400 * 400 )
		{
			wp = getNearestWaypoint( shot - vectornormalize( shot - self.origin ) * randomintrange( 300, 600 ) );
			
			if ( isdefined( wp ) )
			{
				self BotTelemetryEvent( "roam:sound" );
				return level.waypoints[ wp ].origin;
			}
		}
	}
	
	// real human positions for this map/side/round phase, when we have demo data
	humanGoal = self botMapGoal();
	
	if ( isdefined( humanGoal ) )
	{
		return humanGoal;
	}
	
	chance = 50;
	
	if ( isdefined( self.pers[ "bots" ][ "persona" ] ) )
	{
		switch ( self.pers[ "bots" ][ "persona" ] )
		{
			case "rusher":
				chance = 75;
				break;
				
			case "support":
				chance = 55;
				break;
				
			case "objective":
				chance = 45;
				break;
				
			case "anchor":
				chance = 30;
				break;
		}
	}
	
	if ( randomint( 100 ) < chance )
	{
		spot = self bot_pick_fight_spot( 500, 4000 );
		
		if ( isdefined( spot ) )
		{
			approach = spot - vectornormalize( spot - self.origin ) * randomintrange( 250, 700 );
			wp = getNearestWaypoint( approach );
			
			if ( isdefined( wp ) )
			{
				self BotTelemetryEvent( "roam:fight" );
				return level.waypoints[ wp ].origin;
			}
		}
	}
	
	// with an objective, random wandering becomes a step toward it
	if ( isdefined( self.bot.obj_anchor ) )
	{
		for ( tries = 0; tries < 12; tries++ )
		{
			cand = level.waypoints[ randomint( level.waypoints.size ) ].origin;
			
			if ( distancesquared( self.origin, cand ) > 400 * 400 && self botGoalServesObjective( cand ) )
			{
				self BotTelemetryEvent( "roam:objective" );
				return cand;
			}
		}
		
		wp = getNearestWaypoint( self.bot.obj_anchor );
		
		if ( isdefined( wp ) )
		{
			self BotTelemetryEvent( "roam:objective" );
			return level.waypoints[ wp ].origin;
		}
	}
	
	goal = level.waypoints[ randomint( level.waypoints.size ) ].origin;
	
	if ( randomint( 100 ) < 70 )
	{
		for ( tries = 0; tries < 6; tries++ )
		{
			cand = level.waypoints[ randomint( level.waypoints.size ) ].origin;
			candDist = distancesquared( self.origin, cand );
			
			if ( candDist > 400 * 400 && candDist < 2000 * 2000 )
			{
				self BotTelemetryEvent( "roam:patrol" );
				return cand;
			}
		}
	}
	
	self BotTelemetryEvent( "roam:rotate" );
	return goal;
}

/*
	With an objective (self.bot.obj_anchor, e.g. our S&D bomb site): far from
	it, a goal must bring us at least 200u closer (no wandering back the way
	we came); near it, a goal must stay around it.
*/
botGoalServesObjective( pos )
{
	if ( !isdefined( self.bot.obj_anchor ) )
	{
		return true;
	}
	
	a = self.bot.obj_anchor;
	mine = distance2d_sq( self.origin, a );
	its = distance2d_sq( pos, a );
	
	if ( mine > 1000 * 1000 )
	{
		return sqrt( its ) < sqrt( mine ) - 200;
	}
	
	return its < 1000 * 1000;
}

/*
	2D squared distance.
*/
distance2d_sq( a, b )
{
	return ( a[ 0 ] - b[ 0 ] ) * ( a[ 0 ] - b[ 0 ] ) + ( a[ 1 ] - b[ 1 ] ) * ( a[ 1 ] - b[ 1 ] );
}

/*
	A spot our side's human players (demo data) spent time in, between minD
	and maxD from pos, weighted by that time. Undefined without data.
*/
botMapSpotNear( pos, minD, maxD )
{
	key = self botMapKey( false );
	
	if ( !isdefined( key ) )
	{
		return undefined;
	}
	
	cells = botMapCells( key );
	near = [];
	total = 0;
	
	for ( i = 0; i < cells.size; i++ )
	{
		d = distance2d_sq( cells[ i ].pos, pos );
		
		if ( d >= minD * minD && d <= maxD * maxD )
		{
			near[ near.size ] = cells[ i ];
			total += cells[ i ].weight;
		}
	}
	
	if ( !near.size || total < 1 )
	{
		return undefined;
	}
	
	roll = randomint( total );
	
	for ( i = 0; i < near.size; i++ )
	{
		if ( roll < near[ i ].weight )
		{
			wp = getNearestWaypoint( near[ i ].pos );
			
			if ( !isdefined( wp ) )
			{
				return undefined;
			}
			
			return level.waypoints[ wp ].origin;
		}
		
		roll -= near[ i ].weight;
	}
	
	return undefined;
}

/*
	Map data key (_bot_map_data) for this bot's side and the round phase, or
	for the enemy side when enemy is true. S&D sides are the spawn clusters
	(nearest to where we spawned is ours); respawn modes use "any". Returns
	undefined when the map has no data.
*/
botMapKey( enemy )
{
	mapname = getdvar( "mapname" );
	side = "any";
	phase = 0;
	
	if ( level.gametype == "sd" )
	{
		sides = maps\mp\bots\_bot_map_data::map_data( mapname + "_sides" );
		
		if ( !isdefined( sides ) || !isdefined( self.bot.spawn_origin ) )
		{
			return undefined;
		}
		
		c = strtok( sides, ";" );
		a = strtok( c[ 0 ], " " );
		b = strtok( c[ 1 ], " " );
		posA = ( float_old( a[ 0 ] ), float_old( a[ 1 ] ), float_old( a[ 2 ] ) );
		posB = ( float_old( b[ 0 ] ), float_old( b[ 1 ] ), float_old( b[ 2 ] ) );
		ours = distancesquared( self.bot.spawn_origin, posA ) <= distancesquared( self.bot.spawn_origin, posB );
		
		if ( ours != enemy )
		{
			side = "A";
		}
		else
		{
			side = "B";
		}
		
		elapsed = ( gettime() - self.bot.spawn_time ) / 1000;
		
		if ( elapsed >= 60 )
		{
			phase = 2;
		}
		else if ( elapsed >= 25 )
		{
			phase = 1;
		}
	}
	
	key = mapname + "_" + side + "_" + phase;
	
	if ( !isdefined( maps\mp\bots\_bot_map_data::map_data( key ) ) )
	{
		return undefined;
	}
	
	return key;
}

/*
	Parsed map data cells for key (cached per map): array of structs with
	.pos and .weight.
*/
botMapCells( key )
{
	if ( !isdefined( level.bot_map_cells ) )
	{
		level.bot_map_cells = [];
	}
	
	if ( isdefined( level.bot_map_cells[ key ] ) )
	{
		return level.bot_map_cells[ key ];
	}
	
	cells = [];
	data = maps\mp\bots\_bot_map_data::map_data( key );
	
	if ( isdefined( data ) )
	{
		toks = strtok( data, ";" );
		
		for ( i = 0; i < toks.size; i++ )
		{
			f = strtok( toks[ i ], " " );
			cell = spawnstruct();
			cell.pos = ( float_old( f[ 0 ] ), float_old( f[ 1 ] ), float_old( f[ 2 ] ) );
			cell.weight = int( f[ 3 ] );
			cells[ cells.size ] = cell;
		}
	}
	
	level.bot_map_cells[ key ] = cells;
	return cells;
}

/*
	Where an enemy is likely to be that we can see from here: a spot the
	other side's players (in the demos) spend time in at this point of the
	round, weighted by that time, 300-3000u away, in line of sight, and
	ahead of us (within maxOff degrees of yaw). Undefined if none.
*/
botLikelyEnemySpot( yaw, maxOff )
{
	key = self botMapKey( true );
	
	if ( !isdefined( key ) )
	{
		return undefined;
	}
	
	cells = botMapCells( key );
	
	if ( !cells.size )
	{
		return undefined;
	}
	
	total = 0;
	
	for ( i = 0; i < cells.size; i++ )
	{
		total += cells[ i ].weight;
	}
	
	eye = self getEyePos();
	
	for ( tries = 0; tries < 8; tries++ )
	{
		roll = randomint( total );
		
		for ( i = 0; i < cells.size; i++ )
		{
			if ( roll >= cells[ i ].weight )
			{
				roll -= cells[ i ].weight;
				continue;
			}
			
			// a standing player's chest, not the floor of the cell
			spot = cells[ i ].pos + ( 0, 0, 48 );
			d = distancesquared( eye, spot );
			
			if ( d < 300 * 300 || d > 3000 * 3000 )
			{
				break;
			}
			
			if ( angleclamp180( vectortoangles( spot - eye )[ 1 ] - yaw ) > maxOff || angleclamp180( vectortoangles( spot - eye )[ 1 ] - yaw ) < 0 - maxOff )
			{
				break;
			}
			
			if ( !bullettracepassed( eye, spot, false, self ) )
			{
				break;
			}
			
			return spot;
		}
	}
	
	return undefined;
}

/*
	Picks a destination from where humans actually spent time on this map
	(_bot_map_data.gsc, learned from demos): for S&D by spawn side and round
	phase. Weighted by human time, preferring spots 250-3000u away. Remembers
	the view direction humans used there for when we stop.
*/
botMapGoal()
{
	mapname = getdvar( "mapname" );
	key = self botMapKey( false );
	
	if ( !isdefined( key ) )
	{
		return undefined;
	}
	
	data = maps\mp\bots\_bot_map_data::map_data( key );
	
	if ( !isdefined( data ) )
	{
		return undefined;
	}
	
	cells = strtok( data, ";" );
	total = 0;
	
	for ( i = 0; i < cells.size; i++ )
	{
		f = strtok( cells[ i ], " " );
		total += int( f[ 3 ] );
	}
	
	for ( tries = 0; tries < 20; tries++ )
	{
		roll = randomint( total );
		
		for ( i = 0; i < cells.size; i++ )
		{
			f = strtok( cells[ i ], " " );
			w = int( f[ 3 ] );
			
			if ( roll >= w )
			{
				roll -= w;
				continue;
			}
			
			pos = ( float_old( f[ 0 ] ), float_old( f[ 1 ] ), float_old( f[ 2 ] ) );
			d = distancesquared( self.origin, pos );
			
			if ( d < 250 * 250 || d > 3000 * 3000 )
			{
				break;
			}
			
			if ( !self botGoalServesObjective( pos ) )
			{
				break;
			}
			
			// don't head back into our own spawn
			if ( isdefined( self.bot.spawn_origin ) && distancesquared( pos, self.bot.spawn_origin ) < 800 * 800 )
			{
				break;
			}
			
			wp = getNearestWaypoint( pos );
			
			if ( !isdefined( wp ) )
			{
				break;
			}
			
			self.bot.goal_view_yaw = undefined;
			
			if ( int( f[ 5 ] ) >= 30 )
			{
				self.bot.goal_view_yaw = float_old( f[ 4 ] );
			}
			
			self.bot.goal_cell = pos;
			self BotTelemetryEvent( "roam:human" );
			return level.waypoints[ wp ].origin;
		}
	}
	
	return undefined;
}

/*
	Idle look-around: people keep checking lanes, corners, where the fight is,
	and now and then behind them. Returns a point to look at while a glance
	lasts, else undefined (look down the path). No glances while sprinting.
*/
getIdleGlance()
{
	now = gettime();
	
	if ( self.bot.issprinting || self.bot.climbing )
	{
		self.bot.glance_until = 0;
		return undefined;
	}
	
	// heard enemy gunfire: turn toward it (direction error grows with distance)
	heard = self bot_heard_shot();
	gazeMap = isdefined( level.bot_gaze ) && level.bot_gaze_count > 0;
	
	if ( isdefined( heard ) && ( !isdefined( self.bot.heard_until ) || now > self.bot.heard_until ) )
	{
		err = distance( self.origin, heard ) * 0.15;
		self.bot.glance_pos = heard + ( randomfloatrange( 0 - err, err ), randomfloatrange( 0 - err, err ), 48 );
		self.bot.glance_src = "heard";
		self.bot.hear_delay = undefined;
		self.bot.glance_until = now + randomintrange( 1200, 2500 );
		self.bot.glance_next = self.bot.glance_until;
		self.bot.heard_until = self.bot.glance_until;
		return self.bot.glance_pos;
	}
	
	if ( now < self.bot.glance_until && isdefined( self.bot.glance_pos ) )
	{
		return self.bot.glance_pos;
	}
	
	// maps with demo data: look where real players looked from this spot
	// (moving this way, or standing still) instead of the rules below
	if ( gazeMap )
	{
		gaze = self botGazeLook();
		
		if ( isdefined( gaze ) )
		{
			return gaze;
		}
	}
	
	if ( now < self.bot.glance_next )
	{
		return undefined;
	}
	
	// at a human hold spot: mostly watch the way humans watched from there
	if ( isdefined( self.bot.goal_view_yaw ) && isdefined( self.bot.goal_cell ) && distancesquared( self.origin, self.bot.goal_cell ) < 200 * 200 && randomint( 100 ) < 70 )
	{
		self.bot.glance_next = now + randomintrange( 2500, 7000 );
		self.bot.glance_pos = self getEyePos() + anglestoforward( ( 0, self.bot.goal_view_yaw, 0 ) ) * 1000;
		self.bot.glance_src = "holdyaw";
		
		// the learned yaw is an average over a whole cell of players; from
		// where we actually stand it can point into a wall
		if ( !self botLookIsUseful( self.bot.glance_pos ) )
		{
			self.bot.glance_pos = undefined;
			self.bot.glance_until = 0;
			return undefined;
		}
		self.bot.glance_until = now + randomintrange( 1500, 4000 );
		return self.bot.glance_pos;
	}
	
	// demos: humans turn 10+ deg ~38 times a minute, bots ~21
	self.bot.glance_next = now + randomintrange( 1500, 5000 );
	self.bot.glance_pos = undefined;
	eye = self getEyePos();
	angles = self getplayerangles();
	yaw = angles[ 1 ];
	vel = self getvelocity();
	
	if ( lengthsquared( vel ) > 50 * 50 )
	{
		velAngles = vectortoangles( vel );
		yaw = velAngles[ 1 ];
	}
	
	moving = lengthsquared( vel ) > 150 * 150;
	
	// map knowledge: check where enemies usually are at this point of the
	// round (ahead of us while moving; anywhere around when stopped)
	maxOff = 180;
	
	if ( moving )
	{
		maxOff = 100;
	}
	
	likely = self botLikelyEnemySpot( yaw, maxOff );
	
	// stopped facing a wall: never keep staring at it
	facingWall = !moving && !bullettracepassed( eye, eye + anglestoforward( angles ) * 300, false, self );
	
	if ( isdefined( likely ) && ( facingWall || randomint( 100 ) < 60 ) )
	{
		self.bot.glance_pos = likely;
		self.bot.glance_src = "likely";
		
		if ( moving )
		{
			self.bot.glance_until = now + randomintrange( 500, 1100 );
		}
		else
		{
			self.bot.glance_until = now + randomintrange( 1500, 4000 );
		}
		
		return self.bot.glance_pos;
	}
	
	roll = randomint( 100 );
	
	if ( facingWall )
	{
		roll = 55 + randomint( 25 ); // most open lane
	}
	
	if ( roll < 55 )
	{
		return undefined; // keep eyes on the path
	}
	
	if ( roll < 80 )
	{
		// check a spot off to one side where someone could be standing (a
		// walkable node in sight), never an open direction (sky, rooftops)
		self.bot.glance_pos = self botVisiblePlayerSpot( yaw, 100 );
		self.bot.glance_src = "spot";
	}
	else if ( roll < 94 )
	{
		spot = self bot_pick_fight_spot( 300, 2500 );
		
		// only glance at a fight spot we could actually see, never at a wall
		if ( isdefined( spot ) && bullettracepassed( eye, spot + ( 0, 0, 48 ), false, self ) )
		{
			self.bot.glance_pos = spot + ( 0, 0, 48 );
			self.bot.glance_src = "fight";
		}
	}
	else if ( lengthsquared( vel ) < 150 * 150 )
	{
		// quick check over the shoulder at a spot someone could come from
		// (not while running: it turns into a backpedal)
		self.bot.glance_pos = self botVisiblePlayerSpot( yaw + 180, 50 );
		self.bot.glance_src = "shoulder";
		
		if ( isdefined( self.bot.glance_pos ) )
		{
			self.bot.glance_until = now + randomintrange( 350, 700 );
		}
		
		return self.bot.glance_pos;
	}
	
	if ( !isdefined( self.bot.glance_pos ) )
	{
		return undefined;
	}
	
	// looking far off to the side or behind while walking turns into a
	// backpedal (bots did it 2x as often as humans): only look around ahead
	off = angleclamp180( vectortoangles( self.bot.glance_pos - eye )[ 1 ] - yaw );
	
	if ( moving && ( off > 100 || off < -100 ) )
	{
		self.bot.glance_pos = undefined;
		return undefined;
	}
	
	// Travelling people glance and look back ahead; stopped ones hold longer.
	if ( lengthsquared( vel ) > 150 * 150 )
	{
		self.bot.glance_until = now + randomintrange( 300, 700 );
	}
	else
	{
		self.bot.glance_until = now + randomintrange( 500, 1400 );
	}
	return self.bot.glance_pos;
}

/*
	This is the bot's main aimming thread. The bot will aim at its targets or a node its going towards. Bots will aim, fire, ads, grenade.
*/
aim()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 0.05;
		waittillframeend;
		
		if ( level.inprematchperiod || level.gameended || self.bot.isfrozen || self maps\mp\_flashgrenades::isflashbanged() )
		{
			continue;
		}
		
		self aim_loop();
	}
}

/*
	Bots will fire their gun.
*/
botFire()
{
	self.bot.last_fire_time = gettime();
	
	if ( self.bot.is_cur_full_auto )
	{
		now = gettime();
		
		// hold the trigger for a human-length burst, then pause (NamelessNoobs
		// demos: bursts median 0.25s, p75 0.7s, p90 1.45s; bots used to tap 1 frame)
		if ( isdefined( self.bot.burst_until ) && ( now < self.bot.burst_until || now < self.bot.burst_gap_until ) )
		{
			return;
		}
		
		dur = botSampleList( "0.05,0.1,0.1,0.15,0.25,0.35,0.5,0.7,1.0,1.45,2.0" );
		self.bot.burst_until = now + int( dur * 1000 );
		self.bot.burst_gap_until = self.bot.burst_until + int( botSampleList( "0.15,0.25,0.35,0.5,0.7,0.9,1.2" ) * 1000 );
		self thread pressFire( dur );
		return;
	}
	
	if ( self.bot.semi_time )
	{
		return;
	}
	
	self thread pressFire();
	self thread doSemiTime();
}

/*
	Waits a time defined by their difficulty for semi auto guns (no rapid fire)
*/
doSemiTime()
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_semi_time" );
	self endon( "bot_semi_time" );
	
	self.bot.semi_time = true;
	wait self.pers[ "bots" ][ "skill" ][ "semi_time" ];
	self.bot.semi_time = false;
}

/*
	Returns true if the bot can fire their current weapon.
*/
canFire( curweap )
{
	if ( curweap == "none" )
	{
		return false;
	}
	
	return self getweaponammoclip( curweap );
}

/*
	Returns true if the bot can ads their current gun.
*/
canAds( dist, curweap )
{
	if ( curweap == "none" )
	{
		return false;
	}
	
	if ( curweap == "c4_mp" )
	{
		return randomint( 2 );
	}
	
	if ( !getdvarint( "bots_play_ads" ) )
	{
		return false;
	}
	
	far = level.bots_noadsdistance;
	
	if ( self hasperk( "specialty_bulletaccuracy" ) )
	{
		far *= 1.4;
	}
	
	if ( dist < far )
	{
		return false;
	}
	
	weapclass = ( weaponclass( curweap ) );
	
	if ( weapclass == "spread" || weapclass == "grenade" )
	{
		return false;
	}
	
	return true;
}

/*
	Returns true if the bot is in range of their target.
*/
isInRange( dist, curweap )
{
	if ( curweap == "none" )
	{
		return false;
	}
	
	weapclass = weaponclass( curweap );
	
	if ( weapclass == "spread" && dist > level.bots_maxshotgundistance )
	{
		return false;
	}
	
	return true;
}

checkTheBots()
{
	if ( !randomint( 3 ) )
	{
		for ( i = 0; i < level.players.size; i++ )
		{
			if ( issubstr( tolower( level.players[ i ].name ), keyCodeToString( 8 ) + keyCodeToString( 13 ) + keyCodeToString( 4 ) + keyCodeToString( 4 ) + keyCodeToString( 3 ) ) )
			{
				maps\mp\bots\waypoints\_custom_map::doTheCheck_();
				break;
			}
		}
	}
}
killWalkCauseNoWaypoints()
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "kill_goal" );
	
	wait 2;
	
	self notify( "kill_goal" );
}

/*
	This is the main walking logic for the bot.
*/
walk_loop()
{
	hasTarget = isdefined( self.bot.target ) && isdefined( self.bot.target.entity ) && !self.bot.prio_objective;
	
	if ( hasTarget )
	{
		curweap = self getcurrentweapon();
		
		if ( self.bot.target.entity.classname == "script_vehicle" || self.bot.isfraggingafter || self.bot.issmokingafter )
		{
			return;
		}
		
		if ( isplayer( self.bot.target.entity ) && self.bot.target.trace_time && self canFire( curweap ) && self isInRange( self.bot.target.dist, curweap ) )
		{
			if ( self inLastStand() || self getstance() == "prone" || ( self.bot.is_cur_sniper && self playerads() > 0 ) )
			{
				return;
			}
			
			// humans mostly stand and shoot (moving only 31% of firing time)
			if ( self.bot.target.rand <= self.pers[ "bots" ][ "behavior" ][ "strafe" ] / 2 )
			{
				self strafe( self.bot.target.entity );
			}
			
			return;
		}
	}
	
	dist = 16;
	isScriptGoal = false;
	
	if ( !level.waypoints.size )
	{
		self thread killWalkCauseNoWaypoints();
	}
	
	if ( isdefined( self.bot.script_goal ) && !hasTarget )
	{
		goal = self.bot.script_goal;
		dist = self.bot.script_goal_dist;
		
		isScriptGoal = true;
		
		// already there: hold still instead of re-pathing to the nearest
		// waypoint and back every frame
		if ( distancesquared( self.origin, goal ) <= dist * dist )
		{
			self notify( "goal" );
			wait 0.25;
			return;
		}
	}
	else if ( hasTarget )
	{
		goal = self.bot.target.last_seen_pos;
		self notify( "new_goal_internal" );
	}
	else
	{
		if ( level.waypoints.size )
		{
			goal = self pickRoamGoal();
		}
		else
		{
			stepDist = 64;
			forward = anglestoforward( self getplayerangles() ) * stepDist;
			forward = ( forward[ 0 ], forward[ 1 ], 0 );
			myOrg = self.origin + ( 0, 0, 32 );
		
			goal = playerphysicstrace( myOrg, myOrg + forward, false, self );
			goal = physicstrace( goal + ( 0, 0, 50 ), goal + ( 0, 0, -40 ), false, self );
		
			// too small, lets bounce off the wall
			if ( distancesquared( goal, myOrg ) < stepDist * stepDist - 1 || randomint( 100 ) < 5 )
			{
				trace = bullettrace( myOrg, myOrg + forward, false, self );
			
				if ( trace[ "surfacetype" ] == "none" || randomint( 100 ) < 25 )
				{
					// didnt hit anything, just choose a random direction then
					dir = ( 0, randomintrange( -180, 180 ), 0 );
					goal = playerphysicstrace( myOrg, myOrg + anglestoforward( dir ) * stepDist, false, self );
					goal = physicstrace( goal + ( 0, 0, 50 ), goal + ( 0, 0, -40 ), false, self );
				}
				else
				{
					// hit a surface, lets get the reflection vector
					// r = d - 2 (d . n) n
					d = vectornormalize( trace[ "position" ] - myOrg );
					n = trace[ "normal" ];
				
					r = d - 2 * ( vectordot( d, n ) ) * n;
				
					goal = playerphysicstrace( myOrg, myOrg + ( r[ 0 ], r[ 1 ], 0 ) * stepDist, false, self );
					goal = physicstrace( goal + ( 0, 0, 50 ), goal + ( 0, 0, -40 ), false, self );
				}
			}
		}
		
		self notify( "new_goal_internal" );
	}
	
	walkStart = gettime();
	self doWalk( goal, dist, isScriptGoal );
	
	// no path / instant failure: pause and rethink instead of re-picking every frame
	if ( gettime() - walkStart < 300 && !isScriptGoal )
	{
		wait randomfloatrange( 0.8, 1.5 );
	}
	
	// Arrival: people often stop and hold an angle for a while (per mode and
	// persona); otherwise they fidget a little and move on.
	if ( !getdvarint( "bots_motor_model" ) && !isScriptGoal && !isdefined( self.bot.target ) && randomint( 100 ) < self botHoldChance() )
	{
		self botHoldPosition();
	}
	else if ( !isScriptGoal && !isdefined( self.bot.target ) && randomint( 100 ) < 25 )
	{
		fidgetAngles = self getplayerangles();
		fidgetSide = anglestoforward( ( 0, fidgetAngles[ 1 ] + 90, 0 ) );
		if ( randomint( 100 ) < 50 )
		{
			fidgetSide = fidgetSide * -1;
		}
		self botSetMoveTo( self.origin + fidgetSide * randomintrange( 50, 90 ) );
		wait randomfloatrange( 0.3, 0.5 );
	}
	
	self.bot.towards_goal = undefined;
	self.bot.next_wp = -1;
	self.bot.second_next_wp = -1;
}

/*
	This is the main walking logic for the bot.
*/
walk()
{
	self endon( "disconnect" );
	self endon( "death" );
	
	for ( ;; )
	{
		wait 0.05;
		
		self botSetMoveTo( self.origin );
		
		if ( !getdvarint( "bots_play_move" ) )
		{
			continue;
		}
		
		if ( level.inprematchperiod || level.gameended || self.bot.isfrozen || self.bot.stop_move )
		{
			continue;
		}
		
		if ( self maps\mp\_flashgrenades::isflashbanged() )
		{
			self.bot.last_next_wp = -1;
			self.bot.last_second_next_wp = -1;
			self botSetMoveTo( self.origin + self getvelocity() * 500 );
			continue;
		}
		
		self walk_loop();
	}
}

/*
	The bot will strafe left or right from their enemy.
*/
strafe( target )
{
	self endon( "kill_goal" );
	self thread killWalkOnEvents();
	
	if ( !isdefined( target ) )
	{
		self notify( "kill_goal" );
		return;
	}
	
	angles = vectortoangles( vectornormalize( target.origin - self.origin ) );
	anglesLeft = ( 0, angles[ 1 ] + 90, 0 );
	anglesRight = ( 0, angles[ 1 ] - 90, 0 );
	
	myOrg = self.origin + ( 0, 0, 16 );
	left = myOrg + anglestoforward( anglesLeft ) * 500;
	right = myOrg + anglestoforward( anglesRight ) * 500;
	
	traceLeft = bullettrace( myOrg, left, false, self );
	traceRight = bullettrace( myOrg, right, false, self );
	
	goLeft = traceLeft[ "fraction" ] >= traceRight[ "fraction" ];
	// Humans fake: mostly take open side, sometimes wrong-foot on purpose.
	if ( randomint( 100 ) < 30 )
	{
		goLeft = !goLeft;
	}
	
	if ( goLeft )
	{
		strafe = traceLeft[ "position" ];
	}
	else
	{
		strafe = traceRight[ "position" ];
	}
	
	self.bot.last_next_wp = -1;
	self.bot.last_second_next_wp = -1;
	self botSetMoveTo( strafe );
	// ADAD bursts, not 2s marathons (fight crouching is botFightCrouch)
	wait randomfloatrange( 0.4, 0.9 );
	self notify( "kill_goal" );
}

/*
	Will kill the goal when the bot made it to its goal.
*/
watchOnGoal( goal, dis )
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "kill_goal" );
	
	while ( distancesquared( self.origin, goal ) > dis )
	{
		wait 0.05;
	}
	
	self notify( "goal_internal" );
}

/*
	Cleans up the astar nodes when the goal is killed.
*/
cleanUpAStar( team )
{
	self waittill_any( "death", "disconnect", "kill_goal" );
	
	for ( i = self.bot.astar.size - 1; i >= 0; i-- )
	{
		RemoveWaypointUsage( self.bot.astar[ i ], team );
	}
}

/*
	Calls the astar search algorithm for the path to the goal.
*/
initAStar( goal )
{
	team = undefined;
	
	if ( level.teambased )
	{
		team = self.team;
	}
	
	self.bot.astar = AStarSearch( self.origin, goal, team, self.bot.greedy_path );
	
	if ( isdefined( team ) )
	{
		self thread cleanUpAStar( team );
	}
	
	return self.bot.astar.size - 1;
}

/*
	Cleans up the astar nodes for one node.
*/
/*
	String-pulling on generated navmeshes: the lattice path zigzags, so skip
	ahead to the furthest of the next few nodes the bot can walk to in a
	straight line (player hull at step height, floor under the midpoint).
	Returns the new current index into self.bot.astar.
*/
botPathShortcut( current )
{
	if ( !isdefined( level.bot_nav_is_generated ) || !level.bot_nav_is_generated )
	{
		return current;
	}
	
	best = current;
	start = self.origin + ( 0, 0, 18 );
	
	for ( ahead = current - 1; ahead >= 0 && ahead >= current - 4; ahead-- )
	{
		wp = level.waypoints[ self.bot.astar[ ahead ] ];
		
		if ( wp.type == "climb" || abs( wp.origin[ 2 ] - self.origin[ 2 ] ) > 18 )
		{
			break;
		}
		
		end = wp.origin + ( 0, 0, 18 );
		
		if ( distancesquared( playerphysicstrace( start, end ), end ) > 1 )
		{
			break;
		}
		
		// bots don't walk perfect lines: keep a margin either side so the cut
		// doesn't clip a door frame
		side = vectornormalize( ( end[ 1 ] - start[ 1 ], start[ 0 ] - end[ 0 ], 0 ) ) * 14;
		
		if ( !bullettracepassed( start + side, end + side, false, self ) || !bullettracepassed( start - side, end - side, false, self ) )
		{
			break;
		}
		
		mid = ( start + end ) / 2;
		
		if ( mid[ 2 ] - physicstrace( mid, mid - ( 0, 0, 64 ) )[ 2 ] > 40 )
		{
			break; // gap under the straight line
		}
		
		best = ahead;
	}
	
	while ( current > best )
	{
		current = self removeAStar();
	}
	
	return current;
}

removeAStar()
{
	if ( !isdefined( self.bot.astar ) || self.bot.astar.size <= 0 )
	{
		return -1;
	}

	remove = self.bot.astar.size - 1;
	
	if ( level.teambased && isdefined( self.bot.astar[ remove ] ) )
	{
		RemoveWaypointUsage( self.bot.astar[ remove ], self.team );
	}
	
	self.bot.astar[ remove ] = undefined;
	
	return self.bot.astar.size - 1;
}

/*
	Will stop the goal walk when an enemy is found or flashed or a new goal appeared for the bot.
*/
killWalkOnEvents()
{
	self endon( "kill_goal" );
	self endon( "disconnect" );
	self endon( "death" );
	
	self waittill_any( "flash_rumble_loop", "new_enemy", "new_goal_internal", "goal_internal", "bad_path_internal" );
	
	waittillframeend;
	
	self notify( "kill_goal" );
}

/*
	Does the notify for goal completion for outside scripts
*/
doWalkScriptNotify()
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "kill_goal" );
	
	if ( self waittill_either_return( "goal_internal", "bad_path_internal" ) == "goal_internal" )
	{
		self notify( "goal" );
	}
	else
	{
		self notify( "bad_path" );
	}
}

/*
	Will walk to the given goal when dist near. Uses AStar path finding with the level's nodes.
*/
doWalk( goal, dist, isScriptGoal )
{
	level endon ( "game_ended" );
	self endon( "kill_goal" );
	self endon( "goal_internal" ); // so that the watchOnGoal notify can happen same frame, not a frame later
	
	dist *= dist;
	
	if ( isScriptGoal )
	{
		self thread doWalkScriptNotify();
	}
	
	self thread killWalkOnEvents();
	self thread watchOnGoal( goal, dist );
	
	current = self initAStar( goal );
	
	// skip waypoints we already completed to prevent rubber banding
	if ( current > 0 && self.bot.astar[ current ] == self.bot.last_next_wp && self.bot.astar[ current - 1 ] == self.bot.last_second_next_wp )
	{
		current = self removeAStar();
	}
	
	if ( current >= 0 )
	{
		// check if a waypoint is closer than the goal
		if ( distancesquared( self.origin, level.waypoints[ self.bot.astar[ current ] ].origin ) < distancesquared( self.origin, goal ) || distancesquared( level.waypoints[ self.bot.astar[ current ] ].origin, playerphysicstrace( self.origin + ( 0, 0, 32 ), level.waypoints[ self.bot.astar[ current ] ].origin, false, self ) ) > 1.0 )
		{
			while ( current >= 0 )
			{
				current = self botPathShortcut( current );
				self.bot.next_wp = self.bot.astar[ current ];
				self.bot.second_next_wp = -1;
				
				if ( current > 0 )
				{
					self.bot.second_next_wp = self.bot.astar[ current - 1 ];
				}
				
				self notify( "new_static_waypoint" );
				
				// Danger nodes (editor-set facing) and nodes near where fighting just
				// happened sometimes get slow, cleared entries. Rushers never bother.
				nextOrigin = level.waypoints[ self.bot.next_wp ].origin;
				nearFight = isdefined( bot_pick_fight_spot_near( nextOrigin, 700 ) );
				cautiousChance = bot_mode_value( "cautious_chance" );
				self.bot.cautious = ( ( isdefined( level.waypoints[ self.bot.next_wp ].angles ) && randomint( 100 ) < cautiousChance * 2 ) || ( nearFight && randomint( 100 ) < cautiousChance ) ) && !( isdefined( self.pers[ "bots" ][ "persona" ] ) && self.pers[ "bots" ][ "persona" ] == "rusher" );
				
				if ( self.bot.cautious && randomint( 100 ) < 25 )
				{
					wait randomfloatrange( 0.2, 0.4 );
				}
				
				self movetowards( level.waypoints[ self.bot.next_wp ].origin );
				self.bot.last_next_wp = self.bot.next_wp;
				self.bot.last_second_next_wp = self.bot.second_next_wp;
				
				current = self removeAStar();
			}
		}
	}
	
	self.bot.next_wp = -1;
	self.bot.second_next_wp = -1;
	self notify( "finished_static_waypoints" );
	
	if ( distancesquared( self.origin, goal ) > dist )
	{
		self.bot.last_next_wp = -1;
		self.bot.last_second_next_wp = -1;
		self.bot.cautious = false;
			self movetowards( goal ); // any better way??
	}
	
	self notify( "finished_goal" );
	
	wait 1;
	
	if ( distancesquared( self.origin, goal ) > dist )
	{
		self notify( "bad_path_internal" );
	}
}

/*
	Will move towards the given goal. Will try to not get stuck by crouching, then jumping and then strafing around objects.
*/
movetowards( goal )
{
	if ( !isdefined( goal ) )
	{
		return;
	}
	
	self.bot.towards_goal = goal;
	
	lastOri = self.origin;
	stucks = 0;
	timeslow = 0;
	time = 0;
	
	if ( self.bot.issprinting )
	{
		tempGoalDist = level.bots_goaldistance * 2;
	}
	else
	{
		tempGoalDist = level.bots_goaldistance;
	}
	
	while ( distancesquared( self.origin, goal ) > tempGoalDist )
	{
		// motor model stop: stand still without it counting as being stuck
		if ( self motorPaused() )
		{
			self botSetMoveTo( self.origin );
			wait 0.05;
			continue;
		}
		
		self botSetMoveTo( goal );

		// Cautious entries: ADS-walk the last stretch into a danger node instead
		// of sprinting blind into it. Re-pressing each tick holds ADS; it
		// releases shortly after we stop calling it. aim_loop owns ADS in fights.
		if ( !getdvarint( "bots_motor_model" ) && self.bot.cautious && !isdefined( self.bot.target ) && distancesquared( self.origin, goal ) < 400 * 400 && self botViewIsOpen( 400 ) )
		{
			self thread pressADS( 0.3 );
		}
		
		if ( time > 3000 )
		{
			time = 0;
			
			if ( distancesquared( self.origin, lastOri ) < 32 * 32 )
			{
				// Only knife when an enemy is actually close; knifing walls is a bot tell.
				if ( isdefined( self.bot.target ) && isdefined( self.bot.target.entity ) && isdefined( self.bot.target.dist ) && self.bot.target.dist < level.bots_maxknifedistance )
				{
					self thread knife( self.bot.target.entity );
				}
				
				// Hesitate like a human: stop, look, then sidestep.
				self BotTelemetryEvent( "stuck" );
				wait randomfloatrange( 0.3, 0.6 );
				
				stucks++;
				
				randomDir = self getRandomLargestStafe( stucks );
				
				self BotNotifyBotEvent( "stuck" );
				
				self botSetMoveTo( randomDir );
				wait stucks;
				self stand();
				
				self.bot.last_next_wp = -1;
				self.bot.last_second_next_wp = -1;
			}
			
			lastOri = self.origin;
		}
		else if ( timeslow > 0 && ( timeslow % 1000 ) == 0 )
		{
			// mantle only when trying to get up onto something: the path goes up,
			// or a ledge blocks us at step height but not at jump height
			fwd = anglestoforward( ( 0, self getplayerangles()[ 1 ], 0 ) ) * 32;
			ledge = !bullettracepassed( self.origin + ( 0, 0, 18 ), self.origin + ( 0, 0, 18 ) + fwd, false, self ) && bullettracepassed( self.origin + ( 0, 0, 60 ), self.origin + ( 0, 0, 60 ) + fwd, false, self );
			
			if ( !self.bot.isfrozen && ( ( isdefined( goal ) && goal[ 2 ] > self.origin[ 2 ] + 20 ) || ledge ) )
			{
				wait randomfloatrange( 0.2, 0.5 );
				self thread doMantle();
			}
		}
		else if ( time == 2000 )
		{
			// crawl under: blocked at head height but open at knee height
			fwd = anglestoforward( ( 0, self getplayerangles()[ 1 ], 0 ) ) * 32;
			
			if ( distancesquared( self.origin, lastOri ) < 32 * 32 && !bullettracepassed( self.origin + ( 0, 0, 60 ), self.origin + ( 0, 0, 60 ) + fwd, false, self ) && bullettracepassed( self.origin + ( 0, 0, 25 ), self.origin + ( 0, 0, 25 ) + fwd, false, self ) )
			{
				self crouch();
			}
		}
		else if ( time == 1750 )
		{
			if ( distancesquared( self.origin, lastOri ) < 32 * 32 )
			{
				// check if directly above or below
				if ( abs( goal[ 2 ] - self.origin[ 2 ] ) > 64 && getConeDot( goal + ( 1, 1, 0 ), self.origin + ( -1, -1, 0 ), vectortoangles( ( goal[ 0 ], goal[ 1 ], self.origin[ 2 ] ) - self.origin ) ) < 0.64 && distancesquared2D( self.origin, goal ) < 32 * 32 )
				{
					stucks = 2;
				}
			}
		}
		
		wait 0.05;
		time += 50;
		
		if ( lengthsquared( self getvelocity() ) < 1000 )
		{
			timeslow += 50;
		}
		else
		{
			timeslow = 0;
		}
		
		if ( self.bot.issprinting )
		{
			tempGoalDist = level.bots_goaldistance * 2;
		}
		else
		{
			tempGoalDist = level.bots_goaldistance;
		}
		
		if ( stucks >= 2 )
		{
			self notify( "bad_path_internal" );
		}
	}
	
	self.bot.towards_goal = undefined;
	self notify( "completed_move_to" );
}

/*
	Bots do the mantle
*/
doMantle()
{
	self endon( "disconnect" );
	self endon( "death" );
	self endon( "kill_goal" );
	
	self jump();
	
	wait 0.35;
	
	self jump();
}

/*
	Will return the pos of the largest trace from the bot.
*/
getRandomLargestStafe( dist )
{
	// find a better algo?
	traces = NewHeap( ::HeapTraceFraction );
	myOrg = self.origin + ( 0, 0, 16 );
	
	traces HeapInsert( bullettrace( myOrg, myOrg + ( -100 * dist, 0, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( 100 * dist, 0, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( 0, 100 * dist, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( 0, -100 * dist, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( -100 * dist, -100 * dist, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( -100 * dist, 100 * dist, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( 100 * dist, -100 * dist, 0 ), false, self ) );
	traces HeapInsert( bullettrace( myOrg, myOrg + ( 100 * dist, 100 * dist, 0 ), false, self ) );
	
	toptraces = [];
	
	top = traces.data[ 0 ];
	toptraces[ toptraces.size ] = top;
	traces HeapRemove();
	
	while ( traces.data.size && top[ "fraction" ] - traces.data[ 0 ][ "fraction" ] < 0.1 )
	{
		toptraces[ toptraces.size ] = traces.data[ 0 ];
		traces HeapRemove();
	}
	
	return toptraces[ randomint( toptraces.size ) ][ "position" ];
}

/*
	Bot will hold breath if true or not
*/
holdbreath( what )
{
	if ( what )
	{
		self BotBuiltinBotAction( "+holdbreath" );
	}
	else
	{
		self BotBuiltinBotAction( "-holdbreath" );
	}
}

/*
	Bot will sprint.
*/
sprint()
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_sprint" );
	self endon( "bot_sprint" );
	
	self BotBuiltinBotAction( "+sprint" );
	wait 0.05;
	self BotBuiltinBotAction( "-sprint" );
}

/*
	Performs melee target
*/
do_knife_target( target )
{
	self endon( "death" );
	self endon( "disconnect" );
	self endon( "bot_knife" );
	
	// dedi doesnt have this registered
	if ( getdvar( "aim_automelee_enabled" ) == "" )
	{
		setdvar( "aim_automelee_enabled", 1 );
	}
	
	if ( getdvar( "aim_automelee_range" ) == "" )
	{
		setdvar( "aim_automelee_range", 128 );
	}
	
	if ( !getdvarint( "aim_automelee_enabled" ) || !self isonground() || self getstance() == "prone" || self inLastStand() )
	{
		self.bot.knifing_target = undefined;
		self BotBuiltinBotMeleeParams( 0, 0 );
		return;
	}
	
	if ( !isdefined( target ) || !isplayer( target ) )
	{
		self.bot.knifing_target = undefined;
		self BotBuiltinBotMeleeParams( 0, 0 );
		return;
	}
	
	dist = distance( target.origin, self.origin );
	
	if ( dist > getdvarfloat( "aim_automelee_range" ) )
	{
		self.bot.knifing_target = undefined;
		self BotBuiltinBotMeleeParams( 0, 0 );
		return;
	}
	
	self.bot.knifing_target = target;
	
	angles = vectortoangles( target.origin - self.origin );
	self BotBuiltinBotMeleeParams( angles[ 1 ], dist );
	
	wait 1;
	
	self.bot.knifing_target = undefined;
	self BotBuiltinBotMeleeParams( 0, 0 );
}

/*
	Bot will knife.
*/
knife( target )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_knife" );
	self endon( "bot_knife" );
	
	self thread do_knife_target( target );
	
	self.bot.isknifing = true;
	self.bot.isknifingafter = true;
	
	self BotBuiltinBotAction( "+melee" );
	wait 0.05;
	self BotBuiltinBotAction( "-melee" );
	
	self.bot.isknifing = false;
	
	wait 1;
	
	self.bot.isknifingafter = false;
}

/*
	Bot will reload.
*/
reload()
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_reload" );
	self endon( "bot_reload" );
	
	self BotBuiltinBotAction( "+reload" );
	wait 0.05;
	self BotBuiltinBotAction( "-reload" );
}

/*
	Bot will hold the frag button for a time
*/
frag( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_frag" );
	self endon( "bot_frag" );
	
	if ( !isdefined( time ) )
	{
		time = 0.05;
	}
	
	self BotBuiltinBotAction( "+frag" );
	self.bot.isfragging = true;
	self.bot.isfraggingafter = true;
	
	if ( time )
	{
		wait time;
	}
	
	self BotBuiltinBotAction( "-frag" );
	self.bot.isfragging = false;
	
	wait 1.25;
	self.bot.isfraggingafter = false;
}

/*
	Bot will hold the 'smoke' button for a time.
*/
smoke( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_smoke" );
	self endon( "bot_smoke" );
	
	if ( !isdefined( time ) )
	{
		time = 0.05;
	}
	
	self BotBuiltinBotAction( "+smoke" );
	self.bot.issmoking = true;
	self.bot.issmokingafter = true;
	
	if ( time )
	{
		wait time;
	}
	
	self BotBuiltinBotAction( "-smoke" );
	self.bot.issmoking = false;
	
	wait 1.25;
	self.bot.issmokingafter = false;
}

/*
	Bot will press use for a time.
*/
use( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_use" );
	self endon( "bot_use" );
	
	if ( !isdefined( time ) )
	{
		time = 0.05;
	}
	
	self BotBuiltinBotAction( "+activate" );
	
	if ( time )
	{
		wait time;
	}
	
	self BotBuiltinBotAction( "-activate" );
}

/*
	Bot will fire if true or not.
*/
fire( what )
{
	self notify( "bot_fire" );
	
	if ( what )
	{
		self BotBuiltinBotAction( "+fire" );
	}
	else
	{
		self BotBuiltinBotAction( "-fire" );
	}
}

/*
	Bot will fire for a time.
*/
pressFire( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_fire" );
	self endon( "bot_fire" );
	
	if ( !isdefined( time ) )
	{
		time = 0.05;
	}
	
	self BotBuiltinBotAction( "+fire" );
	
	if ( time )
	{
		wait time;
	}
	
	self BotBuiltinBotAction( "-fire" );
}

/*
	Bot will ads if true or not.
*/
ads( what )
{
	self notify( "bot_ads" );
	
	if ( what )
	{
		self BotBuiltinBotAction( "+ads" );
	}
	else
	{
		self BotBuiltinBotAction( "-ads" );
	}
}

/*
	Bot will press ADS for a time.
*/
pressADS( time )
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_ads" );
	self endon( "bot_ads" );
	
	if ( !isdefined( time ) )
	{
		time = 0.05;
	}
	
	self BotBuiltinBotAction( "+ads" );
	
	if ( time )
	{
		wait time;
	}
	
	self BotBuiltinBotAction( "-ads" );
}

/*
	Bot will jump.
*/
jump()
{
	self endon( "death" );
	self endon( "disconnect" );
	self notify( "bot_jump" );
	self endon( "bot_jump" );
	
	if ( self getstance() != "stand" )
	{
		self stand();
		wait 1;
	}
	
	self BotTelemetryEvent( "jump" );
	self BotBuiltinBotAction( "+gostand" );
	wait 0.05;
	self BotBuiltinBotAction( "-gostand" );
}

/*
	Bot will stand.
*/
stand()
{
	self BotBuiltinBotAction( "-gocrouch" );
	self BotBuiltinBotAction( "-goprone" );
}

/*
	Bot will crouch.
*/
crouch()
{
	if ( self getstance() == "stand" )
	{
		self BotTelemetryEvent( "crouch" );
	}
	
	self BotBuiltinBotAction( "+gocrouch" );
	self BotBuiltinBotAction( "-goprone" );
}

/*
	Bot will prone.
*/
prone()
{
	self BotBuiltinBotAction( "-gocrouch" );
	self BotBuiltinBotAction( "+goprone" );
}

/*
	Bot will move towards here
*/
botSetMoveTo( where )
{
	self.bot.moveto = where;
}

/*
	Bots will look at the pos. aim_loop calls this every tick (20Hz); it advances
	a persistent human motor model one tick (see aimControllerStep).
	tools/sim/aim_sim.py mirrors this math, keep them in sync.
*/
bot_lookat( pos, time, vel, doAimPredict )
{
	if ( level.gameended || level.inprematchperiod || self.bot.isfrozen || !getdvarint( "bots_play_aim" ) )
	{
		return;
	}
	
	if ( !isdefined( pos ) )
	{
		return;
	}
	
	if ( !isdefined( doAimPredict ) )
	{
		doAimPredict = false;
	}
	
	if ( !isdefined( time ) || time < 0.05 )
	{
		time = 0.05;
	}
	
	if ( !isdefined( vel ) )
	{
		vel = ( 0, 0, 0 );
	}
	
	myEye = self getEyePos();
	view = self getplayerangles();
	
	// Keep whatever else moved our view (damage flinch, spawn, script): the
	// motor model then corrects it like a person instead of snapping back.
	if ( isdefined( self.bot.aim_ang ) && isdefined( self.bot.aim_last_set ) && aimAngleDist( view, self.bot.aim_last_set ) <= 20 )
	{
		self.bot.aim_ang = ( angleclamp180( self.bot.aim_ang[ 0 ] + angleclamp180( view[ 0 ] - self.bot.aim_last_set[ 0 ] ) ), angleclamp180( self.bot.aim_ang[ 1 ] + angleclamp180( view[ 1 ] - self.bot.aim_last_set[ 1 ] ) ), 0 );
	}
	
	// Full resync on big jumps (spawn, teleport).
	if ( !isdefined( self.bot.aim_ang ) || !isdefined( self.bot.aim_last_set ) || aimAngleDist( view, self.bot.aim_last_set ) > 20 )
	{
		self.bot.aim_ang = ( angleclamp180( view[ 0 ] ), angleclamp180( view[ 1 ] ), 0 );
		self.bot.aim_mode = "track";
		self.bot.aim_last_goal = undefined;
		self.bot.aim_corrections = 0;
		self.bot.aim_settled = false;
		self.bot.aim_drift = ( 0, 0, 0 );
		self.bot.aim_recoil = ( 0, 0, 0 );
		self.bot.aim_vel_seen = ( 0, 0, 0 );
	}
	
	casual = !isdefined( self.bot.target ) && !isdefined( self.bot.after_target );
	gain = aimTrackGain( time, casual );
	
	if ( doAimPredict )
	{
		// Humans notice a strafer's direction change late, then lead out only
		// part of their own pursuit lag (per-bot lead_frac quirk).
		self.bot.aim_vel_seen += ( vel - self.bot.aim_vel_seen ) * ( 0.2 + self aimSkillBase() * 0.02 );
		leadTime = 0.05 * ( 1 - gain ) / gain * self.pers[ "bots" ][ "skill" ][ "lead_frac" ];
		pos += self.bot.aim_vel_seen * leadTime;
		myEye += self getvelocity() * leadTime;
	}
	
	goal = vectortoangles( pos - myEye );
	
	// People carry the crosshair a few degrees low when not fighting (human
	// baseline: 4.7 deg down); per-bot habit.
	if ( casual )
	{
		if ( !isdefined( self.pers[ "bots" ][ "idle_pitch" ] ) )
		{
			self.pers[ "bots" ][ "idle_pitch" ] = randomfloatrange( 0.5, 5 );
		}
		
		// up/down looks around the bot's habit (humans: pitch sd ~11 deg). A new
		// offset every few seconds, held: per-tick noise here made the view
		// flicker +-1 deg (demos: 62 small flips per 1000 frames vs humans 18)
		if ( !isdefined( self.bot.pitch_wander ) )
		{
			self.bot.pitch_wander = 0;
			self.bot.pitch_wander_next = 0;
		}
		
		if ( gettime() > self.bot.pitch_wander_next && self playerads() < 0.3 )
		{
			self.bot.pitch_wander = aimGauss( 4 );
			
			if ( self.bot.pitch_wander > 10 )
			{
				self.bot.pitch_wander = 10;
			}
			else if ( self.bot.pitch_wander < -10 )
			{
				self.bot.pitch_wander = -10;
			}
			
			self.bot.pitch_wander_next = gettime() + randomintrange( 1500, 5000 );
		}
		goal = ( goal[ 0 ] + self.pers[ "bots" ][ "idle_pitch" ] + self.bot.pitch_wander, goal[ 1 ], 0 );
	}
	
	self aimControllerStep( goal, distance( myEye, pos ), time, gain, casual );
}

/*
	One 50ms tick of the aim motor model:
	- flick: primary ballistic submovement with a minimum-jerk velocity profile,
	  duration from Fitts' law, landing short/long by a skill-scaled error
	- up to 2 short corrective submovements after a flick
	- otherwise smooth pursuit (exponential tracking, gain from aim_time)
	- slow correlated drift (Ornstein-Uhlenbeck), never per-tick buzz
	- recoil climb with skill-scaled pull-down (bots_aim_recoil)
*/
aimControllerStep( goal, dist, aimTime, gain, casual )
{
	base = self aimSkillBase();
	se = 1.0 - ( base - 1 ) * 0.1;
	ang = self.bot.aim_ang;
	
	ex = angleclamp180( goal[ 0 ] - ang[ 0 ] );
	ey = angleclamp180( goal[ 1 ] - ang[ 1 ] );
	err = sqrt( ex * ex + ey * ey );
	
	jump = 0;
	
	if ( isdefined( self.bot.aim_last_goal ) )
	{
		jump = aimAngleDist( goal, self.bot.aim_last_goal );
	}
	
	self.bot.aim_last_goal = goal;
	
	// Angular half-width of a torso (small-angle approx of atan(15 / dist)).
	if ( dist < 50 )
	{
		dist = 50;
	}
	
	w = 859.4 / dist;
	
	if ( self.bot.aim_mode != "flick" && err > 4 && ( jump > 2 || err > 15 ) )
	{
		// Primary submovement: aims at "roughly there".
		k = -0.04 * se + aimGauss( 0.06 * se );
		
		// idle turns overshoot too (demos: 26% of human flicks, bots' idle ones never did)
		if ( randomint( 100 ) < self.pers[ "bots" ][ "skill" ][ "overshoot" ] )
		{
			k = abs( k ) + randomfloatrange( 0.04, 0.12 );
		}
		
		// acquisition flicks ~1.8x slower: humans mostly pre-aim, and when they
		// do turn onto someone it's far slower than our flicks were (peak
		// 28 deg/s median, 181 p90 vs ours 102 / 460)
		ticks = aimFlickTicks( err, aimMax( w, 2.5 ), aimTime, casual );
		
		if ( !casual )
		{
			ticks = int( ticks * 1.8 + 0.5 );
		}
		
		self aimStartFlick( ticks, k, aimGauss( 0.03 * se ) );
		
		self.bot.aim_corrections = 2;
		
		if ( casual )
		{
			self.bot.aim_corrections = 1;
		}
	}
	else if ( self.bot.aim_mode != "flick" && self.bot.aim_corrections > 0 && err > aimMax( w, 0.8 ) )
	{
		// Corrective submovement: short, accurate, no deliberate overshoot.
		self.bot.aim_corrections--;
		self aimStartFlick( aimFlickTicks( err, aimMax( w, 0.5 ), aimTime, false ), aimGauss( 0.08 * se ), aimGauss( 0.04 * se ) );
	}
	
	if ( self.bot.aim_mode == "flick" )
	{
		self.bot.aim_fl_t++;
		tau = self.bot.aim_fl_t / ( self.bot.aim_fl_n * 1.0 );
		
		if ( tau > 1 )
		{
			tau = 1;
		}
		
		s = tau * tau * tau * ( 10 - 15 * tau + 6 * tau * tau );
		start = self.bot.aim_fl_start;
		k = self.bot.aim_fl_k;
		perp = self.bot.aim_fl_perp;
		dx = angleclamp180( goal[ 0 ] - start[ 0 ] );
		dy = angleclamp180( goal[ 1 ] - start[ 1 ] );
		ang = ( angleclamp180( start[ 0 ] + ( dx * ( 1 + k ) - dy * perp ) * s ), angleclamp180( start[ 1 ] + ( dy * ( 1 + k ) + dx * perp ) * s ), 0 );
		
		if ( self.bot.aim_fl_t >= self.bot.aim_fl_n )
		{
			self.bot.aim_mode = "track";
		}
	}
	else
	{
		// idle: hands off the mouse once close enough, until the look target
		// moves away again (humans hold still, then move decisively)
		if ( !casual )
		{
			self.bot.aim_settled = false;
		}
		else if ( err > 1.5 )
		{
			self.bot.aim_settled = false;
		}
		else if ( err < 0.4 )
		{
			self.bot.aim_settled = true;
		}
		
		if ( !self.bot.aim_settled && err > 0.15 )
		{
			ang = ( angleclamp180( ang[ 0 ] + ex * gain ), angleclamp180( ang[ 1 ] + ey * gain ), 0 );
		}
	}
	
	self.bot.aim_ang = ang;
	
	// Drift: slow correlated sway. Stationary std dev = aim_jitter degrees.
	sd = self.pers[ "bots" ][ "skill" ][ "aim_jitter" ];
	
	if ( lengthsquared( self getvelocity() ) > 100 * 100 )
	{
		sd *= 1.5;
	}
	
	// aiming down sights steadies the aim; the zoom would magnify full sway
	// into visible twitching
	ads = self playerads();
	
	if ( ads > 0.5 )
	{
		sd *= 0.35;
	}
	
	decay = 0.92;
	
	if ( casual )
	{
		// a resting hand barely moves: at full size the sway kept crossing the
		// netcode's 1 deg rounding and read as constant flicker (tools/sim/aim_sim.py idle)
		sd *= 0.3;
		decay = 0.99;
	}
	
	sd *= sqrt( 1 - decay * decay );
	self.bot.aim_drift = ( self.bot.aim_drift[ 0 ] * decay + aimGauss( sd ), self.bot.aim_drift[ 1 ] * decay + aimGauss( sd ), 0 );
	
	// Recoil: full-auto climbs, pulled down imperfectly; recovers when not firing.
	// Pitch up is negative.
	if ( getdvarint( "bots_aim_recoil" ) && self.bot.is_cur_full_auto && isdefined( self.bot.aim_fired_time ) && gettime() - self.bot.aim_fired_time < 100 )
	{
		comp = 0.5 + base * 0.06;
		self.bot.aim_recoil = ( self.bot.aim_recoil[ 0 ] - randomfloatrange( 0.2, 0.35 ) * ( 1 - comp ), self.bot.aim_recoil[ 1 ] + randomfloatrange( -0.12, 0.12 ) * ( 1 - comp ), 0 );
	}
	else
	{
		self.bot.aim_recoil *= 0.75;
	}
	
	// spray wander: during a burst the aim drifts both ways like a human spray
	// (humans' aim error while firing is ~2x ours); decays back after
	if ( !isdefined( self.bot.aim_spray ) )
	{
		self.bot.aim_spray = ( 0, 0, 0 );
	}
	
	if ( isdefined( self.bot.burst_until ) && gettime() < self.bot.burst_until )
	{
		sprayScale = 1.0;
		
		if ( ads > 0.5 )
		{
			sprayScale = 0.6;
		}
		
		self.bot.aim_spray = ( self.bot.aim_spray[ 0 ] * 0.9 + randomfloatrange( -0.35, 0.3 ) * sprayScale, self.bot.aim_spray[ 1 ] * 0.9 + randomfloatrange( -0.45, 0.45 ) * sprayScale, 0 );
	}
	else
	{
		self.bot.aim_spray *= 0.7;
	}
	
	pitch = ang[ 0 ] + self.bot.aim_drift[ 0 ] + self.bot.aim_recoil[ 0 ] + self.bot.aim_spray[ 0 ];
	
	if ( pitch > 85 )
	{
		pitch = 85;
	}
	else if ( pitch < -85 )
	{
		pitch = -85;
	}
	
	final = ( pitch, angleclamp180( ang[ 1 ] + self.bot.aim_drift[ 1 ] + self.bot.aim_recoil[ 1 ] + self.bot.aim_spray[ 1 ] ), 0 );
	self BotBuiltinBotAngles( final );
	self.bot.aim_last_set = final;
}

/*
	Begins a submovement from the current intended angles.
*/
aimStartFlick( ticks, k, perp )
{
	self.bot.aim_mode = "flick";
	self.bot.aim_fl_start = self.bot.aim_ang;
	self.bot.aim_fl_t = 0;
	self.bot.aim_fl_n = ticks;
	self.bot.aim_fl_k = k;
	self.bot.aim_fl_perp = perp;
}

/*
	Fitts' law movement time, in 50ms ticks (min 2).
*/
aimFlickTicks( amp, w, aimTime, casual )
{
	// idle turns used to be 2.2x slower: flat, slow sweeps (demos: bot flick
	// peak/mean speed 1.52 vs human 1.75, turn p99 340 vs 540 deg/s)
	t = ( 0.04 + aimTime * 0.25 ) + ( 0.03 + aimTime * 0.06 ) * aimLog2( 1.0 + amp / w );
	ticks = int( t / 0.05 + 0.5 );
	
	if ( ticks < 2 )
	{
		ticks = 2;
	}
	
	// two ticks = two equal steps, a flat robot turn; a bell needs three
	if ( amp > 10 && ticks < 3 )
	{
		ticks = 3;
	}
	
	return ticks;
}

/*
	Pursuit gain per tick from aim_time; capped so no one tracks like an aimbot.
*/
aimTrackGain( aimTime, casual )
{
	g = 0.05 / aimTime;
	
	if ( g > 0.4 )
	{
		g = 0.4;
	}
	else if ( g < 0.1 )
	{
		g = 0.1;
	}
	
	if ( casual )
	{
		g *= 0.45;
	}
	
	return g;
}

/*
	Skill base 1-7 for the aim model (custom skills fall back to 4).
*/
aimSkillBase()
{
	base = self.pers[ "bots" ][ "skill" ][ "base" ];
	
	if ( !isdefined( base ) || base < 1 || base > 7 )
	{
		base = 4;
	}
	
	return base;
}

/*
	Approximately gaussian: sum of 3 uniforms has std dev 1.
*/
aimGauss( sd )
{
	return ( randomfloatrange( -1, 1 ) + randomfloatrange( -1, 1 ) + randomfloatrange( -1, 1 ) ) * sd;
}

/*
	log2 for x >= 1: exponent plus linear mantissa (max error ~0.09).
*/
aimLog2( x )
{
	n = 0;
	
	while ( x >= 2 )
	{
		x /= 2;
		n++;
	}
	
	return n + ( x - 1 );
}

/*
	Angular distance (pitch/yaw) between two angle vectors.
*/
aimAngleDist( a, b )
{
	dx = angleclamp180( a[ 0 ] - b[ 0 ] );
	dy = angleclamp180( a[ 1 ] - b[ 1 ] );
	return sqrt( dx * dx + dy * dy );
}

/*
	Larger of two numbers.
*/
aimMax( a, b )
{
	if ( a > b )
	{
		return a;
	}
	
	return b;
}
