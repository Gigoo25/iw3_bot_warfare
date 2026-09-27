// Exports per-snapshot player entity states, player names and every server
// command (chat etc.) from a CoD4/CoD4X .dm_1, using the reference parser
// github.com/Iswenzz/CoD4-DM1 (see tools/demo/extract.sh).
//
// Output (same format tools/demostats.py reads):
//   <base>.players.csv  t,client,team,x,y,z,pitch,yaw,eflags,weapon,ground,evseq,ev0,ev1,ev2,ev3
//   <base>.missiles.csv t,number,weapon,client,other,x,y,z,trtype   (grenades, tubes, rockets)
//   <base>.corpses.csv  t,number,client,x,y,z
//   <base>.meta.json    {names, serverCommands:[{time,text}], snapshots}
#include "API/DemoReader.hpp"
#include "Crypt/Huffman.hpp"

#include <fstream>
#include <iostream>
#include <map>
#include <nlohmann/json.hpp>
#include <set>

using namespace CoD4::DM1;

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::cerr << "usage: export <demo.dm_1> <out-base>" << std::endl;
		return 1;
	}
	Huffman::InitMain();
	DemoReader reader(argv[1]);
	std::string base = argv[2];

	std::ofstream csv(base + ".players.csv");
	csv << "t,client,team,x,y,z,pitch,yaw,eflags,weapon,ground,evseq,ev0,ev1,ev2,ev3\n";

	std::ofstream mcsv(base + ".missiles.csv");
	mcsv << "t,number,weapon,client,other,x,y,z,trtype\n";
	std::ofstream ccsv(base + ".corpses.csv");
	ccsv << "t,number,client,x,y,z\n";

	std::set<int> seen;
	long rows = 0;
	nlohmann::json maps = nlohmann::json::array();
	std::string curServerInfo;
	while (reader.Next())
	{
		Demo &d = *reader.DemoFile;
		const clientSnapshot_t &snap = d.CurrentSnapshot;
		if (!snap.valid || seen.count(snap.messageNum))
			continue;
		seen.insert(snap.messageNum);

		// config strings are replaced on every map load: keep one copy per map
		if (d.ConfigStrings[0] != curServerInfo)
		{
			curServerInfo = d.ConfigStrings[0];
			nlohmann::json cs = nlohmann::json::object();
			for (int i = 0; i < MAX_CONFIGSTRINGS; i++)
				if (!d.ConfigStrings[i].empty())
					cs[std::to_string(i)] = d.ConfigStrings[i];
			maps.push_back({ { "time", snap.serverTime }, { "configStrings", cs } });
		}

		std::map<int, int> team;
		for (int k = 0; k < snap.numClients; k++)
		{
			const clientState_t &c = d.ParseClients[(snap.parseClientsNum + k) & (MAX_PARSE_CLIENTS - 1)];
			team[c.clientIndex] = c.team;
		}
		for (int k = 0; k < snap.numEntities; k++)
		{
			const entityState_t &e = d.ParseEntities[(snap.parseEntitiesNum + k) & (MAX_PARSE_ENTITIES - 1)];
			if (e.eType == ET_MISSILE)
			{
				mcsv << snap.serverTime << ',' << e.number << ',' << e.weapon << ',' << e.ClientNum << ','
					 << e.otherEntityNum << ',' << e.lerp.pos.trBase[0] << ',' << e.lerp.pos.trBase[1] << ','
					 << e.lerp.pos.trBase[2] << ',' << e.lerp.pos.trType << '\n';
				continue;
			}
			if (e.eType == ET_PLAYER_CORPSE)
			{
				ccsv << snap.serverTime << ',' << e.number << ',' << e.ClientNum << ',' << e.lerp.pos.trBase[0] << ','
					 << e.lerp.pos.trBase[1] << ',' << e.lerp.pos.trBase[2] << '\n';
				continue;
			}
			if (e.eType != ET_PLAYER)
				continue;
			int tm = team.count(e.ClientNum) ? team[e.ClientNum] : -1;
			csv << snap.serverTime << ',' << e.ClientNum << ',' << tm << ','
				<< e.lerp.pos.trBase[0] << ',' << e.lerp.pos.trBase[1] << ',' << e.lerp.pos.trBase[2] << ','
				<< e.lerp.apos.trBase[0] << ',' << e.lerp.apos.trBase[1] << ','
				<< e.lerp.eFlags << ',' << e.weapon << ',' << e.groundEntityNum << ',' << e.eventSequence << ','
				<< static_cast<int>(e.events[0]) << ',' << static_cast<int>(e.events[1]) << ','
				<< static_cast<int>(e.events[2]) << ',' << static_cast<int>(e.events[3]) << '\n';
			rows++;
		}
	}

	nlohmann::json meta;
	meta["snapshots"] = seen.size();
	meta["maps"] = maps;
	meta["names"] = nlohmann::json::object();
	for (int i = 0; i < MAX_CLIENTS; i++)
	{
		const clientNames_t &n = reader.DemoFile->ClientNames[i];
		if (!n.netname.empty())
			meta["names"][std::to_string(i)] = { { "name", n.netname }, { "clantag", n.clantag } };
	}
	meta["serverCommands"] = nlohmann::json::array();
	for (const auto &[t, text] : reader.DemoFile->AllServerCommands)
		meta["serverCommands"].push_back({ { "time", t }, { "text", text } });
	std::ofstream(base + ".meta.json") << meta.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);

	std::cout << "players rows " << rows << ", snapshots " << seen.size()
			  << ", clients " << meta["names"].size() << ", serverCommands " << meta["serverCommands"].size() << std::endl;
	return 0;
}
