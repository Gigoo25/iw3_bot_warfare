/*
	_bot_navgen
	Generates a navigation graph for any map, with no hand-made waypoints or
	demo data: flood-fills walkable space from the spawn points, walking every
	link with the player hull (playerphysicstrace) the way a player moves:
	short steps, step-ups of at most STEP_UP, one-way drops off ledges. So
	everything in the graph is reachable and walkable by construction.

	Nodes sit on a lattice (STEP apart); when the straight lattice link is
	blocked, targets shifted sideways are tried so doorways off the lattice
	are still found. The result is cached as a waypoint csv in
	scriptdata/navmesh/ and loaded like any other waypoint file.
*/

#include maps\mp\bots\_bot_utility;

/*
	Cached navmesh file for a map.
*/
navgen_file( mapname )
{
	return "navmesh/" + mapname + "_wp.csv";
}

/*
	Builds the graph for the current map into level.waypoints and caches it.
	Takes a while (it traces the whole map), so it yields every few hundred
	traces; bots wait for level.bot_nav_generating to clear before joining.
*/
navgen_build( mapname )
{
	level.bot_nav_generating = true;
	start = gettime();

	level.navgen_step = getdvarint( "bots_nav_gen_step" );
	level.navgen_traces = 0;
	level.navgen_nodes = [];
	level.navgen_cells = [];
	queue = [];

	// seeds: every spawn point of every mode, dropped to the floor
	classes = strtok( "mp_dm_spawn mp_tdm_spawn mp_tdm_spawn_allies_start mp_tdm_spawn_axis_start mp_sd_spawn_attacker mp_sd_spawn_defender mp_dom_spawn mp_dom_spawn_allies_start mp_dom_spawn_axis_start mp_sab_spawn_allies mp_sab_spawn_axis mp_sab_spawn_allies_start mp_sab_spawn_axis_start", " " );

	for ( c = 0; c < classes.size; c++ )
	{
		spawns = getentarray( classes[ c ], "classname" );

		for ( i = 0; i < spawns.size; i++ )
		{
			org = spawns[ i ].origin;
			floor = playerphysicstrace( org + ( 0, 0, 32 ), org - ( 0, 0, 128 ) );
			ix = int( navgen_round( floor[ 0 ] / level.navgen_step ) );
			iy = int( navgen_round( floor[ 1 ] / level.navgen_step ) );

			if ( isdefined( navgen_find( ix, iy, floor[ 2 ] ) ) )
			{
				continue;
			}

			queue[ queue.size ] = navgen_add( ix, iy, floor );
		}
	}

	dirs = [];
	dirs[ 0 ] = ( 1, 0, 0 );
	dirs[ 1 ] = ( -1, 0, 0 );
	dirs[ 2 ] = ( 0, 1, 0 );
	dirs[ 3 ] = ( 0, -1, 0 );
	dirs[ 4 ] = ( 1, 1, 0 );
	dirs[ 5 ] = ( 1, -1, 0 );
	dirs[ 6 ] = ( -1, 1, 0 );
	dirs[ 7 ] = ( -1, -1, 0 );

	maxNodes = getdvarint( "bots_nav_gen_max" );

	for ( q = 0; q < queue.size; q++ )
	{
		n = queue[ q ];
		node = level.navgen_nodes[ n ];

		for ( d = 0; d < dirs.size; d++ )
		{
			tx = node.ix + int( dirs[ d ][ 0 ] );
			ty = node.iy + int( dirs[ d ][ 1 ] );

			// sideways offsets (perpendicular to the link) find doors off the lattice
			perp = vectornormalize( ( 0 - dirs[ d ][ 1 ], dirs[ d ][ 0 ], 0 ) );
			offsets = [];
			offsets[ 0 ] = 0;
			offsets[ 1 ] = level.navgen_step * 0.4;
			offsets[ 2 ] = level.navgen_step * -0.4;

			for ( o = 0; o < offsets.size; o++ )
			{
				target = ( tx * level.navgen_step, ty * level.navgen_step, 0 ) + perp * offsets[ o ];
				level.navgen_jumped = false;
				floor = navgen_walk( node.origin, target );

				if ( !isdefined( floor ) )
				{
					continue;
				}

				other = navgen_find( tx, ty, floor[ 2 ] );

				if ( !isdefined( other ) )
				{
					if ( level.navgen_nodes.size >= maxNodes )
					{
						break;
					}

					other = navgen_add( tx, ty, floor );
					queue[ queue.size ] = other;
				}

				if ( other != n )
				{
					navgen_link( n, other );
					
					if ( level.navgen_jumped )
					{
						level.navgen_nodes[ other ].jump = true;
					}
				}

				break;
			}
		}

		if ( level.navgen_traces > 400 )
		{
			level.navgen_traces = 0;
			wait 0.05;
		}
	}

	navgen_prune();
	navgen_center();
	navgen_install();

	BotBuiltinPrintConsole( "Navmesh: generated " + level.waypoints.size + " nodes for " + mapname + " in " + ( ( gettime() - start ) / 1000 ) + "s." );
	navgen_save( navgen_file( mapname ) );

	level.navgen_nodes = undefined;
	level.navgen_cells = undefined;
	level.bot_nav_generating = false;
}

/*
	Walks from a floor position to target (x/y) like a player: short moves
	with the hull raised by the step height, then down to the floor. A
	blocked move is retried in smaller moves, the way players climb steep
	stairs one frame at a time. Returns the floor position reached, or
	undefined if blocked or over a pit.
*/
navgen_walk( from, target )
{
	stepLen = 16;
	maxDrop = 160;
	
	dist = sqrt( distancesquared2D( from, target ) );
	steps = int( ( dist + stepLen - 1 ) / stepLen );
	
	if ( steps < 1 )
	{
		return undefined;
	}
	
	cur = from;
	dropped = 0;
	
	for ( i = 1; i <= steps; i++ )
	{
		frac = i / steps;
		want = ( from[ 0 ] + ( target[ 0 ] - from[ 0 ] ) * frac, from[ 1 ] + ( target[ 1 ] - from[ 1 ] ) * frac, 0 );
		f = navgen_move( cur, want, maxDrop - dropped, 18 );
		
		if ( !isdefined( f ) )
		{
			// steep stairs: four small moves, each allowed its own step-up
			f = cur;
			
			for ( m = 1; m <= 4 && isdefined( f ); m++ )
			{
				mid = ( cur[ 0 ] + ( want[ 0 ] - cur[ 0 ] ) * m / 4, cur[ 1 ] + ( want[ 1 ] - cur[ 1 ] ) * m / 4, 0 );
				f = navgen_move( f, mid, maxDrop - dropped, 18 );
			}
		}
		
		if ( !isdefined( f ) )
		{
			// too high to step up: jump it (CoD4 jumps ~39u; bots jump onto
			// step-height obstacles ahead of them while moving)
			f = navgen_move( cur, want, maxDrop - dropped, 36 );
			
			if ( !isdefined( f ) )
			{
				return undefined;
			}
			
			level.navgen_jumped = true;
		}
		
		if ( f[ 2 ] < cur[ 2 ] - 18 )
		{
			dropped += cur[ 2 ] - f[ 2 ];
		}
		
		cur = f;
	}
	
	return cur;
}

/*
	One player move from floor position cur to want (x/y): hull raised by
	stepUp (step height, or jump height), then down to the floor within maxDrop. Returns the new
	floor position, or undefined.
*/
navgen_move( cur, want, maxDrop, stepUp )
{
	up = cur + ( 0, 0, stepUp );
	want = ( want[ 0 ], want[ 1 ], up[ 2 ] );
	
	p = playerphysicstrace( up, want );
	level.navgen_traces++;
	
	if ( distancesquared2D( p, want ) > 1 )
	{
		return undefined;
	}
	
	f = playerphysicstrace( p, p - ( 0, 0, stepUp + maxDrop ) );
	level.navgen_traces++;
	
	if ( p[ 2 ] - f[ 2 ] >= stepUp + maxDrop - 0.5 )
	{
		return undefined; // no floor within reach: pit or off the map
	}
	
	return f;
}

/*
	Node in lattice cell (ix, iy) at about height z, or undefined.
*/
navgen_find( ix, iy, z )
{
	key = ix + "," + iy;

	if ( !isdefined( level.navgen_cells[ key ] ) )
	{
		return undefined;
	}

	ids = level.navgen_cells[ key ];

	for ( i = 0; i < ids.size; i++ )
	{
		if ( abs( level.navgen_nodes[ ids[ i ] ].origin[ 2 ] - z ) < 48 )
		{
			return ids[ i ];
		}
	}

	return undefined;
}

/*
	Adds a node, returns its index.
*/
navgen_add( ix, iy, origin )
{
	node = spawnstruct();
	node.ix = ix;
	node.iy = iy;
	node.origin = origin;
	node.children = [];

	id = level.navgen_nodes.size;
	level.navgen_nodes[ id ] = node;

	key = ix + "," + iy;

	if ( !isdefined( level.navgen_cells[ key ] ) )
	{
		level.navgen_cells[ key ] = [];
	}

	level.navgen_cells[ key ][ level.navgen_cells[ key ].size ] = id;
	return id;
}

/*
	Directed link a -> b (b -> a is tested when b expands).
*/
navgen_link( a, b )
{
	kids = level.navgen_nodes[ a ].children;

	for ( i = 0; i < kids.size; i++ )
	{
		if ( kids[ i ] == b )
		{
			return;
		}
	}

	level.navgen_nodes[ a ].children[ kids.size ] = b;
}

/*
	Keeps only nodes that can reach the first spawn node and be reached
	from it (its strongly connected component), so no node is a trap a
	bot could drop into but never get out of. Re-indexes the rest.
*/
navgen_prune()
{
	n = level.navgen_nodes.size;
	
	if ( !n )
	{
		return;
	}
	
	// reverse links
	parents = [];
	
	for ( i = 0; i < n; i++ )
	{
		parents[ i ] = [];
	}
	
	for ( i = 0; i < n; i++ )
	{
		kids = level.navgen_nodes[ i ].children;
		
		for ( k = 0; k < kids.size; k++ )
		{
			parents[ kids[ k ] ][ parents[ kids[ k ] ].size ] = i;
		}
	}
	
	fwd = navgen_reach( 0, true, parents );
	back = navgen_reach( 0, false, parents );
	
	newId = [];
	keep = [];
	
	for ( i = 0; i < n; i++ )
	{
		if ( isdefined( fwd[ i ] ) && isdefined( back[ i ] ) )
		{
			newId[ i ] = keep.size;
			keep[ keep.size ] = level.navgen_nodes[ i ];
		}
	}
	
	for ( i = 0; i < keep.size; i++ )
	{
		kids = [];
		
		for ( k = 0; k < keep[ i ].children.size; k++ )
		{
			c = keep[ i ].children[ k ];
			
			if ( isdefined( newId[ c ] ) )
			{
				kids[ kids.size ] = newId[ c ];
			}
		}
		
		keep[ i ].children = kids;
	}
	
	BotBuiltinPrintConsole( "Navmesh: kept " + keep.size + " of " + n + " nodes (dropped one-way dead ends)." );
	level.navgen_nodes = keep;
}

/*
	Moves nodes in narrow spaces (doorways, corridors) to the middle, so
	paths run through the centre of a door instead of along its frame:
	per axis, if the player hull has less than 96u of room, shift halfway
	toward the roomier side (at most 24u) if the floor stays level.
*/
navgen_center()
{
	moved = 0;
	
	for ( i = 0; i < level.navgen_nodes.size; i++ )
	{
		org = level.navgen_nodes[ i ].origin;
		up = org + ( 0, 0, 18 );
		shift = ( 0, 0, 0 );
		axes = [];
		axes[ 0 ] = ( 1, 0, 0 );
		axes[ 1 ] = ( 0, 1, 0 );
		
		for ( a = 0; a < axes.size; a++ )
		{
			pos = distance( up, playerphysicstrace( up, up + axes[ a ] * 48 ) );
			neg = distance( up, playerphysicstrace( up, up - axes[ a ] * 48 ) );
			
			if ( pos + neg >= 96 )
			{
				continue;
			}
			
			d = ( pos - neg ) / 2;
			
			if ( d > 24 )
			{
				d = 24;
			}
			else if ( d < -24 )
			{
				d = -24;
			}
			
			shift += axes[ a ] * d;
		}
		
		if ( lengthsquared( shift ) < 4 )
		{
			continue;
		}
		
		p = playerphysicstrace( up, up + shift );
		f = playerphysicstrace( p, p - ( 0, 0, 40 ) );
		
		if ( abs( f[ 2 ] - org[ 2 ] ) <= 18 )
		{
			level.navgen_nodes[ i ].origin = f;
			moved++;
		}
		
		if ( i % 100 == 99 )
		{
			wait 0.05;
		}
	}
	
	BotBuiltinPrintConsole( "Navmesh: centred " + moved + " nodes in narrow spaces." );
}

/*
	Nodes reachable from start following links forward (or backward).
	Returns an array keyed by node index.
*/
navgen_reach( start, forward, parents )
{
	seen = [];
	seen[ start ] = true;
	queue = [];
	queue[ 0 ] = start;
	
	for ( q = 0; q < queue.size; q++ )
	{
		if ( forward )
		{
			next = level.navgen_nodes[ queue[ q ] ].children;
		}
		else
		{
			next = parents[ queue[ q ] ];
		}
		
		for ( k = 0; k < next.size; k++ )
		{
			if ( !isdefined( seen[ next[ k ] ] ) )
			{
				seen[ next[ k ] ] = true;
				queue[ queue.size ] = next[ k ];
			}
		}
		
		if ( q % 500 == 499 )
		{
			wait 0.05;
		}
	}
	
	return seen;
}

/*
	Turns the generated nodes into level.waypoints.
*/
navgen_install()
{
	wps = [];

	for ( i = 0; i < level.navgen_nodes.size; i++ )
	{
		wp = spawnstruct();
		wp.origin = level.navgen_nodes[ i ].origin;
		wp.children = level.navgen_nodes[ i ].children;
		wp.type = "stand";
		
		if ( isdefined( level.navgen_nodes[ i ].jump ) )
		{
			wp.type = "climb"; // reached by a jump: stay standing on the way there
		}
		wps[ i ] = wp;
	}

	level.waypoints = wps;
}

/*
	Writes level.waypoints in the waypoint csv format.
*/
navgen_save( filename )
{
	f = BotBuiltinFileOpen( filename, "write" );

	if ( f < 1 )
	{
		BotBuiltinPrintConsole( "Navmesh: could not write " + filename );
		return;
	}

	BotBuiltinWriteLine( f, level.waypoints.size );

	for ( i = 0; i < level.waypoints.size; i++ )
	{
		wp = level.waypoints[ i ];
		str = wp.origin[ 0 ] + " " + wp.origin[ 1 ] + " " + wp.origin[ 2 ] + ",";

		// every node needs a child token: an empty field shifts the csv columns
		if ( !wp.children.size )
		{
			str += i;
		}

		for ( h = 0; h < wp.children.size; h++ )
		{
			if ( h )
			{
				str += " ";
			}

			str += wp.children[ h ];
		}

		str += "," + wp.type + ",,,";
		BotBuiltinWriteLine( f, str );
	}

	BotBuiltinFileClose( f );
	BotBuiltinPrintConsole( "Navmesh: saved " + filename );
}

/*
	Dev tool: set bots_nav_probe "x1 y1 z1 x2 y2 z2" and the traces the
	generator relies on are printed for that segment.
*/
navgen_probe_watch()
{
	for ( ;; )
	{
		wait 0.5;
		v = getdvar( "bots_nav_probe" );
		
		if ( v == "" )
		{
			continue;
		}
		
		setdvar( "bots_nav_probe", "" );
		t = strtok( v, " " );
		
		if ( t.size < 6 )
		{
			continue;
		}
		
		a = ( float_old( t[ 0 ] ), float_old( t[ 1 ] ), float_old( t[ 2 ] ) );
		b = ( float_old( t[ 3 ] ), float_old( t[ 4 ] ), float_old( t[ 5 ] ) );
		
		p = playerphysicstrace( a + ( 0, 0, 18 ), b + ( 0, 0, 18 ) );
		BotBuiltinPrintConsole( "Probe hull: reached " + p + " of " + ( b + ( 0, 0, 18 ) ) );
		
		for ( h = 10; h <= 70; h += 20 )
		{
			bt = bullettrace( a + ( 0, 0, h ), b + ( 0, 0, h ), true, undefined );
			ent = "none";
			
			if ( isdefined( bt[ "entity" ] ) )
			{
				ent = bt[ "entity" ].classname;
				
				if ( isdefined( bt[ "entity" ].targetname ) )
				{
					ent += "/" + bt[ "entity" ].targetname;
				}
			}
			
			BotBuiltinPrintConsole( "Probe bullet +" + h + ": fraction " + bt[ "fraction" ] + " entity " + ent + " surface " + bt[ "surfacetype" ] );
		}
	}
}

/*
	Rounds to the nearest integer.
*/
navgen_round( v )
{
	if ( v < 0 )
	{
		return 0 - int( 0.5 - v );
	}

	return int( v + 0.5 );
}
