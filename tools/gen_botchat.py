#!/usr/bin/env python3
"""
Writes scriptdata/botchat.txt (category|lang|text), the line pool for
bots_chat_human. Style follows what real CoD4x lobbies look like in 2026
(C4S public chatlog, sampled 2026-09-26): short (median 8 chars), ~75%
lowercase, typos, gg/ggff, rekt/lmfao/omg, jugg/sniper/fps complaints, hacker
accusations, greetings like "ello"/"holaa", console commands typed into chat by
mistake (cg_fov 80, !fps), and a lot of Spanish/Italian. Lines are original.

{name} is replaced with a cleaned/shortened player name.
Categories: greet kill streak death death_repeat gg idle
            reply_hi reply_gg reply_lol reply_hack reply_bots
"""

LINES = {
	"en": {
		"leave": ["gtg", "bye", "gn", "cya", "gotta go", "bye all", "gn all", "dinner", "bed time", "later", "cya guys", "k im off"],
		"rage_leave": ["this server sucks", "im out", "wtf this lag", "cant hit anything", "ffs", "done", "bs spawns", "lol ok"],
		"greet": ["hi", "hey", "ello", "hello all", "yo", "sup", "hi guys", "evening", "hey all", "o/", "hiya", "back"],
		"kill": ["lol", "rekt", "ez", "sorry {name}", "sry", "haha", "gotcha", "nt {name}", "close one", "lmao", "oops",
			"bye", "xd", "noob", "boom", "hehe", "{name} lol", "ur welcome", "phew", "sit", "that was close"],
		"streak": ["on fire", "ez", "cant stop", "uav up", "lol this team", "who wants some", "heli soon", "5 in a row", "tryhard mode"],
		"death": ["wtf", "lag", "how", "omg", "ffs", "bs", "nice shot", "ns", "lol", "damn", "ugh", "rip", "wow", "no way",
			"hitreg lol", "i shot first", "what", "fml", "lucky", "sniper again", "jugg noob", "martyrdom lol", "noob tube",
			"camper", "nice camp", "brb", "k", "..."],
		"death_repeat": ["{name} again..", "ok {name} chill", "{name} stop", "nice wh", "wallhack much?", "report {name}",
			"{name} is hacking", "how does {name} see me", "{name} u camping there all game?", "lol {name}", "again??",
			"{name} gg u win", "who is {name}"],
		"gg": ["gg", "gg", "GG", "gg wp", "ggs", "gg all", "ggff", "gg ez", "wp", "gg next map", "close game", "gg team"],
		"idle": ["lag?", "fps drops again", "this map again", "rtv", "anyone else lagging", "admin?", "where is everyone",
			"cg_fov 80", "cg_fov 65", "!fps", "\\", "/kill", "brb", "back", "afk 1 min", "my ping lol", "why so many snipers",
			"no uav?", "this server is dead", "one more map then bed", "anyone from uk?", "doors?", "k"],
		"reply_hi": ["hi", "hey", "yo", "o/", "hello", "sup"],
		"reply_gg": ["gg", "gg", "ggs", "wp"],
		"reply_lol": ["lol", "xd", "haha", "lmao"],
		"reply_hack": ["lol no", "just good", "ok", "cry more", "report then", "?", "nah", "sure"],
		"reply_bots": ["?", "idk", "lol", "who cares", "whatever", "dunno", "ask admin", "maybe"],
	},
	"es": {
		"leave": ["me voy", "chao", "adios", "hasta luego"],
		"rage_leave": ["me voy de este server", "que asco"],
		"greet": ["hola", "holaa", "buenas", "hola a todos", "wenas"],
		"kill": ["jaja", "jajaja", "toma", "facil", "ez", "sorry", "fuera", "adios"],
		"streak": ["imparable", "jaja que malos"],
		"death": ["que", "lag", "pff", "que malo", "joder", "no puede ser", "de lejos", "camper", "hacker", "madre mia", "vaya"],
		"death_repeat": ["{name} otra vez", "{name} hacker", "menudo wallhack lleva {name}", "es hacker si", "{name} tramposo"],
		"gg": ["gg", "gg wp", "buena partida"],
		"idle": ["alguien de espana?", "hay lag", "otro mapa", "cg_fov 80", "hola?"],
		"reply_hi": ["hola", "buenas", "hola!"],
		"reply_gg": ["gg"],
		"reply_lol": ["jajaja", "jaja"],
		"reply_hack": ["que dices", "no", "jaja no"],
		"reply_bots": ["?", "ni idea", "jaja"],
	},
	"pt": {
		"leave": ["flw", "vlw", "tchau"],
		"rage_leave": ["lixo de server"],
		"greet": ["oi", "eae", "salve", "fala galera"],
		"kill": ["kkk", "kkkk", "toma", "ez", "foi mal"],
		"streak": ["ta facil"],
		"death": ["q isso", "lag", "vish", "pqp", "noob", "camper", "hacker"],
		"death_repeat": ["{name} de novo", "{name} hack", "wall {name}"],
		"gg": ["gg", "gg wp"],
		"idle": ["alguem br?", "lag", "cg_fov 80"],
		"reply_hi": ["oi", "salve"],
		"reply_gg": ["gg"],
		"reply_lol": ["kkkk"],
		"reply_hack": ["q nada", "kkk"],
		"reply_bots": ["?", "sei la"],
	},
	"it": {
		"leave": ["ciao", "vado"],
		"rage_leave": ["basta"],
		"greet": ["ciao", "ciao a tutti", "bella"],
		"kill": ["ahah", "preso", "ez", "scusa"],
		"streak": ["troppo facile"],
		"death": ["ma dai", "lag", "che cosa", "camper", "hacker", "mamma mia"],
		"death_repeat": ["{name} ancora", "{name} hacker", "wall {name}"],
		"gg": ["gg", "gg wp"],
		"idle": ["italiani?", "c'e lag", "cg_fov 80"],
		"reply_hi": ["ciao"],
		"reply_gg": ["gg"],
		"reply_lol": ["ahahah"],
		"reply_hack": ["ma va", "no"],
		"reply_bots": ["?", "boh"],
	},
	"de": {
		"leave": ["bin weg", "gn8", "tschuess"],
		"rage_leave": ["kein bock mehr"],
		"greet": ["hi", "moin", "servus", "n abend"],
		"kill": ["haha", "sry", "ez", "tschau"],
		"streak": ["laeuft"],
		"death": ["was", "lag", "boah", "camper", "noob", "wtf", "alter"],
		"death_repeat": ["{name} schon wieder", "{name} wh", "{name} hacker"],
		"gg": ["gg", "gg wp"],
		"idle": ["deutsche hier?", "lag?", "cg_fov 80"],
		"reply_hi": ["moin", "hi"],
		"reply_gg": ["gg"],
		"reply_lol": ["haha"],
		"reply_hack": ["noe", "lol"],
		"reply_bots": ["?", "keine ahnung"],
	},
	"pl": {
		"leave": ["nara", "spadam"],
		"rage_leave": ["mam dosc"],
		"greet": ["siema", "elo", "czesc"],
		"kill": ["haha", "sorki", "ez", "nara"],
		"streak": ["ez"],
		"death": ["co", "lag", "kurde", "camper", "cheater", "serio"],
		"death_repeat": ["{name} znowu", "{name} ma wh", "{name} cheater"],
		"gg": ["gg", "gg wp"],
		"idle": ["polacy?", "lagi", "cg_fov 80"],
		"reply_hi": ["siema", "elo"],
		"reply_gg": ["gg"],
		"reply_lol": ["xd"],
		"reply_hack": ["nie", "xd"],
		"reply_bots": ["?", "nie wiem"],
	},
}


def main():
	out = []
	for lang, cats in LINES.items():
		for cat, lines in cats.items():
			for line in lines:
				assert "|" not in line and ";" not in line and '"' not in line, line
				assert line.isascii(), line  # CoD4 chat is not reliably unicode-safe
				out.append(f"{cat}|{lang}|{line}")
	with open("scriptdata/botchat.txt", "wb") as f:
		f.write(("\r\n".join(out) + "\r\n").encode("ascii"))
	print(f"{len(out)} lines")


if __name__ == "__main__":
	main()
