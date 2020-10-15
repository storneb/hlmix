#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Niveh"
#define PLUGIN_VERSION "1.7"
#define NONE 0
#define SPEC 1
#define TEAM1 2
#define TEAM2 3
#define MAX_ID 32
#define MAX_CLIENTS 129
#define MAX_NAME 96
#define GAME_UNKNOWN 0
#define GAME_CSTRIKE 1
#define WARMUP 1
#define KNIFE_ROUND 2
#define MATCH 3

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

EngineVersion g_Game;

public Plugin myinfo = 
{
	name = "[HLMIX] Simple plugin de automix para los servidores de CSGO", 
	author = "automaric", 
	description = "Simple plugin de automix para los servidores de CSGO", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/automaric"
};

ConVar SetMaxPausesPerTeamSMP = null;
ConVar RequiredReadyPlayers = null;
Handle hSetModel = INVALID_HANDLE;
Handle hDrop = INVALID_HANDLE;
Handle PlayersReadyList;
Handle gh_SilentPrefixes = INVALID_HANDLE;
Handle gh_Prefixes = INVALID_HANDLE;
char gs_Prefixes[32];
char gs_SilentPrefixes[32];
char choice0[] = "LoadConfigWarmup";
char choice1[] = "LoadConfigKnifeRound";
char choice2[] = "ForcePauseSMP";
char choice3[] = "ForceUnPauseSMP";
char choice4[] = "SetCaptainT";
char choice5[] = "SetCaptainCT";
char choice6[] = "Command_Spec";
char choice7[] = "Command_Team";
char choice8[] = "Command_Swap";
char choice9[] = "Command_TeamSwap";
char choice10[] = "Command_Exchange";
char choice11[] = "ResetTeamPausesSMP";
char choice12[] = "KickBotsSMP";
char choice13[] = "PluginHelpCvarsSMP";
char MessageFormat[512] = "[\x04AUTOMIX\x01] \x04({DMG_TO} in {HITS_TO}) \x01given, \x07({DMG_FROM} in {HITS_FROM}) \x01taken, \x0B{NAME} ({HEALTH} hp)";
char ClientSteamID[32];
bool TacticUnpauseCT;
bool g_bLog = false;
bool TacticUnpauseT;
bool StayUsed;
bool UnpauseLock;
bool SwitchUsed;
bool TeamsWereSwapped;
bool ManualCaptain;
bool CaptainsSelected;
bool CaptainMenu;
bool ReadyLock;
int CurrentRound;
int ReadyPlayers;
int CaptainCT;
int CaptainT;
int Damage[MAXPLAYERS + 1][MAXPLAYERS + 1];
int Hits[MAXPLAYERS + 1][MAXPLAYERS + 1];
char CaptainID_CT[40];
char CaptainID_T[40];
char ClientCheck[40];
char TeamName_T[64];
char TeamName_CT[64];
char CaptainName_T[64];
char CaptainName_CT[64];
char selected_player_global[40];
char selected_player_global_exchange[40];
char selected_player_global_exchange_with[40];
int MoneyOffset;
int RoundsWon_T;
int RoundsWon_CT;
int team_t;
int team_ct;
int WinningTeam;
int KRWinner;
int TotalPausesCT;
int TotalPausesT;
int MaxPausesCT;
int MaxPausesT;
int game = GAME_UNKNOWN;


char teams[4][16] = 
{
	"N/A", 
	"SPEC", 
	"T", 
	"CT"
};

char t_models[4][PLATFORM_MAX_PATH] = 
{
	"models/player/t_phoenix.mdl", 
	"models/player/t_leet.mdl", 
	"models/player/t_arctic.mdl", 
	"models/player/t_guerilla.mdl"
};

char ct_models[4][PLATFORM_MAX_PATH] = 
{
	"models/player/ct_urban.mdl", 
	"models/player/ct_gsg9.mdl", 
	"models/player/ct_sas.mdl", 
	"models/player/ct_gign.mdl"
};

//Code by X@IDER
DropWeapon(client, ent)
{
	if (hDrop != INVALID_HANDLE)
		SDKCall(hDrop, client, ent, 0, 0);
	else
	{
		char edict[MAX_NAME];
		GetEdictClassname(ent, edict, sizeof(edict));
		FakeClientCommandEx(client, "use %s;drop", edict);
	}
}
//Code by X@IDER
ExchangePlayers(client, cl1, cl2)
{
	int t1 = GetClientTeam(cl1);
	int t2 = GetClientTeam(cl2);
	if (((t1 == TEAM1) && (t2 == TEAM2)) || ((t1 == TEAM2) && (t2 == TEAM1)))
	{
		ChangeClientTeamEx(cl1, t2);
		ChangeClientTeamEx(cl2, t1);
	} else
		ReplyToCommand(client, "Bad targets");
}

stock bool IsPaused()
{
	return GameRules_GetProp("m_bMatchWaitingForResume") != 0;
}

stock bool PausesLimitReachedCT()
{
	if ((SetMaxPausesPerTeamSMP.IntValue == TotalPausesCT))
	{
		return true;
	}
	return false;
}

stock bool PausesLimitReachedT()
{
	if ((SetMaxPausesPerTeamSMP.IntValue == TotalPausesT))
	{
		return true;
	}
	return false;
}

public OnMapStart()
{
	GetTeamName(TEAM1, teams[TEAM1], MAX_ID);
	GetTeamName(TEAM2, teams[TEAM2], MAX_ID);
	TacticUnpauseCT = false;
	TacticUnpauseT = false;
	UnpauseLock = false;
	ReadyPlayers = 0;
	TotalPausesCT = 0;
	TotalPausesT = 0;
	StayUsed = false;
	TeamsWereSwapped = false;
	SwitchUsed = false;
	int MaxPausesPerTeam = SetMaxPausesPerTeamSMP.IntValue;
	MaxPausesCT = MaxPausesPerTeam;
	MaxPausesT = MaxPausesPerTeam;
	CaptainMenu = false;
	ManualCaptain = true;
	ServerCommand("smpadmin_warmup");
	ResetValues();
	ClearArray(PlayersReadyList);
	CurrentRound = WARMUP;
}

public void OnClientDisconnect(client)
{
	if (PlayerReadyCheck(client))
	{
		char DisconnectedPlayer[32];
		GetClientAuthId(client, AuthId_Steam2, DisconnectedPlayer, sizeof(DisconnectedPlayer), false);
		int DisPlayerIndex = FindStringInArray(PlayersReadyList, DisconnectedPlayer);
		ReadyPlayers--;
		RemoveFromArray(PlayersReadyList, DisPlayerIndex);
	}
}

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if (g_Game != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	
	SetMaxPausesPerTeamSMP = CreateConVar("smp_pause_limit", "3", "Set maximum allowed pauses PER TEAM", _, true, 0.0, true, 1337.0);
	RequiredReadyPlayers = CreateConVar("smp_ready_players_needed", "10", "Set required ready players needed", _, true, 1.0, true, 10.0);
	
	//Code by ofir753
	gh_Prefixes = CreateConVar("prefix_chars", ".", "Prefix chars for commands max 32 chars Example:\".[-\"", _);
	gh_SilentPrefixes = CreateConVar("prefix_silentchars", "", "Prefix chars for hidden commands max 32 chars Example:\".[-\"", _);
	
	HookConVarChange(gh_Prefixes, Action_OnSettingsChange);
	HookConVarChange(gh_SilentPrefixes, Action_OnSettingsChange);
	GetConVarString(gh_Prefixes, gs_Prefixes, sizeof(gs_Prefixes));
	GetConVarString(gh_SilentPrefixes, gs_SilentPrefixes, sizeof(gs_SilentPrefixes));
	AutoExecConfig(true, "multiprefixes");
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	LoadTranslations("hlmix.phrases");
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	HookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath);
	MoneyOffset = FindSendPropOffs("CCSPlayer", "m_iAccount");
	
	PlayersReadyList = CreateArray(40);
	
	AddCommandListener(Join_Team, "jointeam");
	RegConsoleCmd("sm_stay", StaySMP, "No team change (after knife round)");
	RegConsoleCmd("sm_switch", SwitchSMP, "Change teams (after knife round)");
	RegConsoleCmd("sm_version", PluginVersionSMP, "Show SMP version");
	RegConsoleCmd("sm_pauses_used", ShowPausesUsedSMP, "Show player's team pauses used");
	RegConsoleCmd("sm_help", PluginHelpSMP, "Show player commands");
	RegConsoleCmd("sm_unpause", TacticUnpauseSMP, "Team tactic unpause");
	RegConsoleCmd("sm_pause", TacticPauseSMP, "Team tactic pause");
	RegConsoleCmd("sm_ready", ReadySMP, "Set yourself as Ready.");
	RegConsoleCmd("sm_gaben", ReadySMP, "Same as !ready");
	RegConsoleCmd("sm_unready", UnreadySMP, "Set yourself as Unready.");
	RegAdminCmd("smpadmin_match", Ladder5on5SMP, ADMFLAG_ROOT, "Load 5on5 Config");
	RegAdminCmd("smpadmin_kniferound_random", KnifeRoundRandom, ADMFLAG_ROOT, "Random captains knife round when no admin is online");
	RegAdminCmd("smpadmin_warmup", LoadConfigWarmup, ADMFLAG_GENERIC, "Load warmup config");
	RegAdminCmd("smpadmin_kniferound", LoadConfigKnifeRound, ADMFLAG_GENERIC, "Load knife round Config");
	RegAdminCmd("smpadmin_help", PluginHelpAdminSMP, ADMFLAG_GENERIC, "Show SMP help");
	RegAdminCmd("smpadmin_pause", ForcePauseSMP, ADMFLAG_GENERIC, "Force pause (Admin only)");
	RegAdminCmd("smpadmin_unpause", ForceUnPauseSMP, ADMFLAG_GENERIC, "Force unpause (Admin only)");
	RegAdminCmd("smpadmin_team_pauses_reset", ResetTeamPausesSMP, ADMFLAG_GENERIC, "Reset team pauses count");
	RegAdminCmd("smpadmin_bot_kick", KickBotsSMP, ADMFLAG_GENERIC, "Kick all bots");
	RegAdminCmd("smpadmin_help_cvars", PluginHelpCvarsSMP, ADMFLAG_GENERIC, "Admin's cvars help");
	RegAdminCmd("smpadmin_swap", Command_Swap, ADMFLAG_GENERIC, "Move a player to the other team");
	RegAdminCmd("smpadmin_teamswap", Command_TeamSwap, ADMFLAG_GENERIC, "Swap teams with each other");
	RegAdminCmd("smpadmin_exchange", Command_Exchange, ADMFLAG_GENERIC, "Exchange player from team A with a player from team B");
	RegAdminCmd("smpadmin_getcaptain_t", GetCaptainT, ADMFLAG_GENERIC, "Get new captain for team T");
	RegAdminCmd("smpadmin_getcaptain_ct", GetCaptainCT, ADMFLAG_GENERIC, "Get new captain for team CT");
	RegAdminCmd("smpadmin_spec", Command_Spec, ADMFLAG_GENERIC, "move player to spec");
	RegAdminCmd("smpadmin_team", Command_Team, ADMFLAG_GENERIC, "change player's team");
	RegAdminCmd("sm_smpadmin", OpenAdminMenuSMP, ADMFLAG_GENERIC, "Open admin menu (SMP)");
	
	CurrentRound = WARMUP;
}

//Code by ofir753
public Action_OnSettingsChange(Handle cvar, const char[] oldvalue, const char[] newvalue)
{
	if (cvar == gh_Prefixes)
	{
		strcopy(gs_Prefixes, sizeof(gs_Prefixes), newvalue);
	}
	else if (cvar == gh_SilentPrefixes)
	{
		strcopy(gs_SilentPrefixes, sizeof(gs_SilentPrefixes), newvalue);
	}
}
//Code by ofir753
public Action Command_Say(client, const char[] command, argc)
{
	char sText[300];
	char sSplit[2];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	for (new i = 0; i < strlen(gs_Prefixes); i++)
	{
		if (sText[0] == gs_Prefixes[i])
		{
			if (sText[1] == '\0' || sText[1] == ' ')
				return Plugin_Continue;
			Format(sSplit, sizeof(sSplit), "%c", gs_Prefixes[i]);
			if (!SplitStringRight(sText, sSplit, sText, sizeof(sText)))
			{
				return Plugin_Continue;
			}
			FakeClientCommand(client, "sm_%s", sText);
			return Plugin_Continue;
		}
	}
	for (new i = 0; i < strlen(gs_SilentPrefixes); i++)
	{
		if (sText[0] == gs_SilentPrefixes[i])
		{
			if (sText[1] == '\0' || sText[1] == ' ')
				return Plugin_Continue;
			Format(sSplit, sizeof(sSplit), "%c", gs_SilentPrefixes[i]);
			if (!SplitStringRight(sText, sSplit, sText, sizeof(sText)))
			{
				return Plugin_Continue;
			}
			FakeClientCommand(client, "sm_%s", sText);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
//Code by ofir753
stock bool SplitStringRight(const char[] source, const char[] split, char[] part, partLen) //Thanks to KissLick https://forums.alliedmods.net/member.php?u=210752
{
	int index = StrContains(source, split); // get start index of split string
	
	if (index == -1) // split string not found..
		return false;
	
	index += strlen(split); // get end index of split string    
	strcopy(part, partLen, source[index]); // copy everything after source[ index ] to part
	return true;
}

public Action Event_ServerCvar(Handle event, const char[] name, bool dontBroadcast)
{
	dontBroadcast = true;
	return Plugin_Handled;
}

public Action OpenAdminMenuSMP(client, args)
{
	AdminMenuSMP(client);
}

public Action Join_Team(client, const char[] command, args)
{
	char team[5];
	GetCmdArg(1, team, sizeof(team));
	int target = StringToInt(team);
	int current = GetClientTeam(client);
	
	if (CurrentRound == WARMUP)
	{
		if (target == TEAM1 || target == TEAM2)
		{
			PrintHintText(client, "%d/%d Jugadores listos > Escribe !ready para estar listo.", client, ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
		}
	}
	
	if (current == TEAM1 || current == TEAM2 || current == SPEC)
	{
		if (CurrentRound == WARMUP)
		{
			if (target == SPEC || target == NONE)
			{
				return Plugin_Handled;
			}
		}
		else if (CurrentRound == KNIFE_ROUND || CurrentRound == MATCH)
		{
			if (target == TEAM1 || target == TEAM2 || target == SPEC || target == NONE)
			{
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}
//Code by X@IDER
public Action Command_Team(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[\x04AUTOMIX\x01] smpadmin_team <target> <team>");
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	char buffer[MAX_NAME];
	char team[MAX_ID];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, team, sizeof(team));
	int tm = StringToInt(team);
	int targets[MAX_CLIENTS];
	bool ml = false;
	
	int count = ProcessTargetString(pattern, client, targets, sizeof(targets), 0, buffer, sizeof(buffer), ml);
	
	for (new i = 0; i < count; i++)
	{
		ChangeClientTeamEx(targets[i], tm);
	}
	return Plugin_Handled;
}

public SetTeamMenu(client)
{
	Handle menu = CreateMenu(MenuHandler_SetTeamMenu);
	SetMenuTitle(menu, "%T", "Set Team Menu", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_SetTeamMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Set Team Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global, sizeof(selected_player_global));
			SetTeamMenu_TeamSelect(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public SetTeamMenu_TeamSelect(client)
{
	Handle menu = CreateMenu(MenuHandler_SetTeamMenu_TeamSelect);
	SetMenuTitle(menu, "%T", "Set Team Select Menu", LANG_SERVER);
	AddMenuItem(menu, "CT", "CT");
	AddMenuItem(menu, "T", "T");
	AddMenuItem(menu, "SPEC", "Spec");
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_SetTeamMenu_TeamSelect(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Set Team Select Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, "CT"))
			{
				ServerCommand("smpadmin_team %s 3", selected_player_global);
				AdminMenuSMP(param1);
			}
			else if (StrEqual(info, "T"))
			{
				ServerCommand("smpadmin_team %s 2", selected_player_global);
				AdminMenuSMP(param1);
			}
			else if (StrEqual(info, "SPEC"))
			{
				ServerCommand("smpadmin_team %s 1", selected_player_global);
				AdminMenuSMP(param1);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

//Code by X@IDER
public Action Command_Spec(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[\x04AUTOMIX\x01] Introduzca un objetivo.");
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	char buffer[MAX_NAME];
	GetCmdArg(1, pattern, sizeof(pattern));
	int targets[MAX_CLIENTS];
	bool ml;
	
	int count = ProcessTargetString(pattern, client, targets, sizeof(targets), 0, buffer, sizeof(buffer), ml);
	
	for (new i = 0; i < count; i++)
	{
		int t = targets[i];
		if (IsPlayerAlive(t))ForcePlayerSuicide(t);
		ChangeClientTeam(t, SPEC);
	}
	return Plugin_Handled;
}

public SpecMenu(client)
{
	Handle menu = CreateMenu(MenuHandler_SpecMenu);
	SetMenuTitle(menu, "%T", "Spec Menu", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_SpecMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Spec Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
			
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			ServerCommand("smpadmin_spec %s", selection_Name);
			AdminMenuSMP(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public CaptainMenuForAdmin(client)
{
	Handle menu = CreateMenu(MenuHandler_ChooseCaptain_Question);
	SetMenuTitle(menu, "%T", "Manual Captain Question", LANG_SERVER);
	AddMenuItem(menu, "Y", "Yes");
	AddMenuItem(menu, "N", "No");
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public CT_ChooseCaptainForAdmin(client)
{
	Handle menu = CreateMenu(MenuHandler_ChooseCaptain_CT);
	SetMenuTitle(menu, "%T", "Manual Captain Selection CT", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		char CT_ClientUserID[40];
		int CT_ClientID = GetClientUserId(i);
		IntToString(CT_ClientID, CT_ClientUserID, sizeof(CT_ClientUserID));
		char CT_ClientName[40];
		GetClientName(i, CT_ClientName, sizeof(CT_ClientName));
		AddMenuItem(menu, CT_ClientUserID, CT_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public T_ChooseCaptainForAdmin(client)
{
	Handle menu = CreateMenu(MenuHandler_ChooseCaptain_T);
	SetMenuTitle(menu, "%T", "Manual Captain Selection T", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_T)
			continue;
		
		char T_ClientUserID[40];
		int T_ClientID = GetClientUserId(i);
		IntToString(T_ClientID, T_ClientUserID, sizeof(T_ClientUserID));
		char T_ClientName[40];
		GetClientName(i, T_ClientName, sizeof(T_ClientName));
		AddMenuItem(menu, T_ClientUserID, T_ClientName);
	}
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_ChooseCaptain_Question(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Manual Captain Question", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, "Y"))
			{
				ManualCaptain = true;
				CaptainMenu = true;
				CT_ChooseCaptainForAdmin(param1);
			}
			
			else if (StrEqual(info, "N"))
			{
				ManualCaptain = false;
				CaptainMenu = true;
				LoadConfigKnifeRound(param1, args);
			}
			else
			{
				PrintToChat(param1, "ERROR!");
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public MenuHandler_ChooseCaptain_CT(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Manual Captain Selection CT", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_CT = selection_SteamID;
			CaptainName_CT = selection_Name;
			PrintToChatAll("[\x04AUTOMIX\x01]\x04 %s \x01Ha sido seleccionado como capitan del lado \x07CT!", selection_Name);
			T_ChooseCaptainForAdmin(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public MenuHandler_ChooseCaptain_T(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Manual Captain Selection T", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			CaptainsSelected = true;
			CaptainMenu = true;
			char selection_SteamID[40];
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientAuthId(selection_UserID, AuthId_Steam2, selection_SteamID, sizeof(selection_SteamID), false);
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			CaptainID_T = selection_SteamID;
			CaptainName_T = selection_Name;
			PrintToChatAll("[\x04AUTOMIX\x01]\x04 %s \x01Ha sido seleccionado como capitan del lado \x07T!", selection_Name);
			LoadConfigKnifeRound(param1, args);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

/*Soon to be fixed (causing errors)
public void SetClientTags()
{
	if (CurrentRound == WARMUP)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientValid(i))
				continue;

			if (PlayerReadyCheck(i))
			{
				CS_SetClientClanTag(i, "[READY]");
			}
			else if (!PlayerReadyCheck(i))
			{
				CS_SetClientClanTag(i, "[UNREADY]");
			}
		}
	}
	else if (CurrentRound == MATCH)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (CaptainCheck(i))
			{
				CS_SetClientClanTag(i, "[CAPTAIN]");
			}
			else if (!CaptainCheck(i))
			{
				CS_SetClientClanTag(i, "[PLAYER]");
			}
		}
	}
	else if (CurrentRound == KNIFE_ROUND)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			CS_SetClientClanTag(i, "");
		}
	}
} */

public bool AllReadyCheck()
{
	if (AllReady() && CurrentRound == WARMUP)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public bool PlayerReadyCheck(client)
{
	if (IsPlayerReady(client) && CurrentRound == WARMUP)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public int PlayersIngame()
{
	int IngamePlayersCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			IngamePlayersCount++;
		}
	}
	return IngamePlayersCount;
}

public bool AllReady()
{
	int ReqReady = GetConVarInt(RequiredReadyPlayers);
	if (ReadyPlayers == ReqReady)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public Action ReadySMP(client, args)
{
	char ReadyAttemptSteamID[32];
	char ReadyAttemptName[32];
	int AdminCount = 0;
	int AdminUserId;
	ReadyLock = false;
	if (CurrentRound == WARMUP)
	{
		if (IsClientValid(client) && !AllReadyCheck() && !PlayerReadyCheck(client) && ClientTeamValid(client) & !ReadyLock)
		{
			int ReqRdy = GetConVarInt(RequiredReadyPlayers);
			GetClientAuthId(client, AuthId_Steam2, ReadyAttemptSteamID, sizeof(ReadyAttemptSteamID), false);
			GetClientName(client, ReadyAttemptName, sizeof(ReadyAttemptName));
			PushArrayString(PlayersReadyList, ReadyAttemptSteamID);
			ReadyPlayers++;
			PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01ahora esta listo. %d/%d jugadores listos.", ReadyAttemptName, ReadyPlayers, ReqRdy);
			PrintHintTextToAll("%d/%d Jugadores listos > Escribe !ready para estar listo.", ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
		}
		if (AllReadyCheck())
		{
			ReadyLock = true;
			PrintToChatAll("[\x04AUTOMIX\x01] Todos los jugadores estan listos! El Match comenzara en breve.");
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientValid(i))
				{
					AdminId AdminID = GetUserAdmin(i);
					if (AdminID != INVALID_ADMIN_ID)
					{
						AdminUserId = GetClientUserId(i);
						AdminCount++;
					}
				}
			}
			if (AdminCount == 0)
			{
				CreateTimer(5.0, KnifeRoundRandomTimer);
			}
			else if (AdminCount > 0)
			{
				int Admin = GetClientOfUserId(AdminUserId);
				CaptainMenuForAdmin(Admin);
			}
		}
	}
	else if (CurrentRound != WARMUP)
	{
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action UnreadySMP(client, args)
{
	char UnreadyAttemptSteamID[32];
	char UnreadyAttemptName[32];
	GetClientName(client, UnreadyAttemptName, sizeof(UnreadyAttemptName));
	if (CurrentRound == WARMUP)
	{
		if (IsClientValid(client) && PlayerReadyCheck(client))
		{
			GetClientAuthId(client, AuthId_Steam2, UnreadyAttemptSteamID, sizeof(UnreadyAttemptSteamID), false);
			if (FindStringInArray(PlayersReadyList, UnreadyAttemptSteamID) != -1)
			{
				int ReqRdy = GetConVarInt(RequiredReadyPlayers);
				int ArrayIndex = FindStringInArray(PlayersReadyList, UnreadyAttemptSteamID);
				RemoveFromArray(PlayersReadyList, ArrayIndex);
				ReadyPlayers--;
				PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01No esta listo. %d/%d jugadores listos.", UnreadyAttemptName, ReadyPlayers, ReqRdy);
				PrintHintTextToAll("%d/%d Jugadores listos > Escribe !ready para estar listo.", ReadyPlayers, GetConVarInt(RequiredReadyPlayers));
				return Plugin_Handled;
			}
		}
	}
	else if (CurrentRound != WARMUP)
	{
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public bool IsPlayerReady(client)
{
	GetClientAuthId(client, AuthId_Steam2, ClientSteamID, sizeof(ClientSteamID), false);
	if (FindStringInArray(PlayersReadyList, ClientSteamID) != -1)
	{
		return true;
	}
	return false;
}

public AdminMenuSMP(client)
{
	Handle menu = CreateMenu(AdminMenuHandlerSMP, MENU_ACTIONS_ALL);
	SetMenuTitle(menu, "%T", "Menu de administrador", LANG_SERVER);
	AddMenuItem(menu, choice0, "Iniciar calentamiento");
	AddMenuItem(menu, choice1, "Forzar ronda de cuchillo");
	AddMenuItem(menu, choice2, "Pause at freezetime");
	AddMenuItem(menu, choice3, "Unpause");
	AddMenuItem(menu, choice4, "Escoger nuevo capitan T");
	AddMenuItem(menu, choice5, "Escoger nuevo capitan CT");
	AddMenuItem(menu, choice6, "Mover jugador a Espectador");
	AddMenuItem(menu, choice7, "Establecer el equipo del jugador");
	AddMenuItem(menu, choice8, "Cambiar jugador de equipo");
	AddMenuItem(menu, choice9, "Cambiar equipos");
	AddMenuItem(menu, choice10, "Intercambiar jugadores");
	AddMenuItem(menu, choice11, "Restablecer las pauses del equipo");
	AddMenuItem(menu, choice12, "Expulsar a los bots");
	AddMenuItem(menu, choice13, "Mostrar cvars");
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 60);
}

public AdminMenuHandlerSMP(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Start:
		{
			PrintToServer("Displaying menu");
		}
		
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Menu de administrador", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			int args;
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if (StrEqual(info, choice0))
			{
				LoadConfigWarmup(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice1))
			{
				LoadConfigKnifeRound(param1, args);
			}
			
			else if (StrEqual(info, choice2))
			{
				ForcePauseSMP(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice3))
			{
				ForceUnPauseSMP(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice4))
			{
				GetCaptainT(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice5))
			{
				GetCaptainCT(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice6))
			{
				SpecMenu(param1);
			}
			
			else if (StrEqual(info, choice7))
			{
				SetTeamMenu(param1);
			}
			
			else if (StrEqual(info, choice8))
			{
				SwapMenu(param1);
			}
			
			else if (StrEqual(info, choice9))
			{
				Command_TeamSwap(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice10))
			{
				ExchangePlayersMenu(param1);
			}
			
			else if (StrEqual(info, choice11))
			{
				ResetTeamPausesSMP(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice12))
			{
				KickBotsSMP(param1, args);
				AdminMenuSMP(param1);
			}
			
			else if (StrEqual(info, choice13))
			{
				PrintToConsole(param1, "[\x04AUTOMIX\x01] sm_cvar smp_set_pause_limit NUMBER \x04-> \x01establecer limite de pausas permitidas por equipo");
				PrintToConsole(param1, "[\x04AUTOMIX\x01] sm_cvar smp_ready_players_needed NUMBER \x04-> \x01jugadores requeridos para ronda de cuchillo");
				PrintToChat(param1, "[\x04AUTOMIX\x01] Compruebe su consola para ver si hay cvars.");
				AdminMenuSMP(param1);
			}
		}
		
		case MenuAction_Cancel:
		{
			PrintToServer("Client %d's menu was cancelled for reason %d", param1, param2);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info), style);
			return style;
		}
	}
	return 0;
}
public Action StaySMP(client, args)
{
	if (WinningTeam == CS_TEAM_T)
	{
		if (GetClientTeam(client) == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (CanUseStay())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01decidio quedarse!", CaptainName_T);
					ForceUnPauseSMP(client, args);
					StayUsed = true;
					CreateTimer(2.0, StartMatch);
					return Plugin_Handled;
				}
			}
		}
	}
	
	else if (WinningTeam == CS_TEAM_CT)
	{
		if (GetClientTeam(client) == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (CanUseStay())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01decidio quedarse", CaptainName_CT);
					ForceUnPauseSMP(client, args);
					StayUsed = true;
					CreateTimer(2.0, StartMatch);
					return Plugin_Handled;
				}
			}
		}
	}
	
	PrintToChat(client, "[\x04AUTOMIX\x01] No puedes usar este comando.");
	return Plugin_Handled;
}

public Action SwitchSMP(client, args)
{
	if (WinningTeam == CS_TEAM_T)
	{
		if (GetClientTeam(client) == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (CanUseSwitch())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01decidio cambiar de lado!", CaptainName_T);
					Command_TeamSwap(client, args);
					ForceUnPauseSMP(client, args);
					SwitchUsed = true;
					TeamsWereSwapped = true;
					CreateTimer(2.0, StartMatch);
					return Plugin_Handled;
				}
			}
		}
	}
	
	else if (WinningTeam == CS_TEAM_CT)
	{
		if (GetClientTeam(client) == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (CanUseSwitch())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] \x06%s \x01decidio cambiar de lado!", CaptainName_CT);
					Command_TeamSwap(client, args);
					ForceUnPauseSMP(client, args);
					SwitchUsed = true;
					TeamsWereSwapped = true;
					CreateTimer(2.0, StartMatch);
					return Plugin_Handled;
				}
			}
		}
	}
	
	PrintToChat(client, "[\x04AUTOMIX\x01] No puedes usar este comando.");
	return Plugin_Handled;
}

static void DamagePrint(int client)
{
	if (!IsClientValid(client))
		return;
	
	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
		return;
	
	//Credits to splewis
	char message[512];
	int otherTeam = (team == CS_TEAM_T) ? CS_TEAM_CT : CS_TEAM_T;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i) && GetClientTeam(i) == otherTeam)
		{
			int health = IsPlayerAlive(i) ? GetClientHealth(i) : 0;
			char name[64];
			GetClientName(i, name, sizeof(name));
			Format(message, sizeof(message), MessageFormat);
			
			ReplaceStringWithInt(message, sizeof(message), "{DMG_TO}", Damage[client][i]);
			ReplaceStringWithInt(message, sizeof(message), "{HITS_TO}", Hits[client][i]);
			ReplaceStringWithInt(message, sizeof(message), "{DMG_FROM}", Damage[i][client]);
			ReplaceStringWithInt(message, sizeof(message), "{HITS_FROM}", Hits[i][client]);
			ReplaceString(message, sizeof(message), "{NAME}", name);
			ReplaceStringWithInt(message, sizeof(message), "{HEALTH}", health);
			PrintToChat(client, message);
		}
	}
	PrintToChat(client, "[\x04AUTOMIX\x01]\x0B----------------------------------------------------------------------");
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	bool validAttacker = IsClientValid(attacker);
	bool validVictim = IsClientValid(victim);
	
	if (validAttacker && validVictim)
	{
		// concept by splewis
		int client_health = GetClientHealth(victim);
		int health_damage = event.GetInt("dmg_health");
		int event_client_health = event.GetInt("health");
		if (event_client_health == 0) {
			health_damage += client_health;
		}
		Damage[attacker][victim] += health_damage;
		Hits[attacker][victim]++;
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (CurrentRound == MATCH)
	{
		if (IsClientValid(victim))
		{
			PrintHintText(victim, "Frags: %d > Deaths: %d > MVPS: %d", victim, GetClientFrags(victim), GetClientDeaths(victim), CS_GetMVPCount(victim));
		}
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	int Cash[MAXPLAYERS + 1];
	int count = 0;
	int money;
	char p_name[64];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 1; j <= MaxClients; j++)
		{
			Damage[i][j] = 0;
			Hits[i][j] = 0;
		}
		if (CurrentRound == MATCH)
		{
			if (IsClientValid(i) && ClientTeamValid(i))
			{
				Cash[count] = i;
				count++;
			}
		}
	}
	if (CurrentRound == MATCH)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientValid(i) && ClientTeamValid(i))
				PrintToChat(i, "[\x04AUTOMIX\x01] ------------------------\x04Dinero del equipo\x01-------------------------");
			
			for (new j = 0; j < count; j++)
			{
				GetClientName(Cash[j], p_name, sizeof(p_name));
				if (IsClientValid(i))
				{
					if (GetClientTeam(i) == GetClientTeam(Cash[j]))
					{
						money = GetEntData(Cash[j], MoneyOffset);
						PrintToChat(i, "[\x04AUTOMIX\x01] El jugador \x04%s \x01tiene \x04$%d", p_name, money);
					}
				}
			}
			if (IsClientValid(i) && ClientTeamValid(i))
				PrintToChat(i, "[\x04AUTOMIX\x01] ----------------------------------------------------------------------");
		}
	}
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (CurrentRound == KNIFE_ROUND)
	{
		WinningKnifeRoundTeam();
		WinningTeam = KRWinner;
		ServerCommand("mp_pause_match");
		if (WinningTeam == CS_TEAM_T)
		{
			PrintToChatAll("[\x04AUTOMIX\x01] \x01El equipo terrorista gana la ronda!");
			PrintToChatAll("[\x04AUTOMIX\x01] \x01Captain elige \x04%s, \x04!stay \x01o \x04!switch", CaptainName_T);
		}
		else if (WinningTeam == CS_TEAM_CT)
		{
			PrintToChatAll("[\x04AUTOMIX\x01] \x01El equipo Anti-Terrorista gana la ronda!");
			PrintToChatAll("[\x04AUTOMIX\x01] \x01Capitan Elige \x04%s, \x04!stay \x01o \x04!switch", CaptainName_CT);
		}
		return Plugin_Handled;
	}
	
	else if (CurrentRound == WARMUP)
	{
		return Plugin_Handled;
	}
	
	else if (CurrentRound == MATCH)
	{
		RoundsWon_T = CS_GetTeamScore(CS_TEAM_T);
		RoundsWon_CT = CS_GetTeamScore(CS_TEAM_CT);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientValid(i)) {
				PrintToChat(i, "[\x04AUTOMIX\x01] ------------------------\x04Reporte de daño\x01-------------------------");
				DamagePrint(i);
				if (IsPlayerAlive(i))
					PrintHintText(i, "Frags: %d > Deaths: %d > MVPS: %d", i, GetClientFrags(i), GetClientDeaths(i), CS_GetMVPCount(i));
			}
		}
		//Format(TeamName_T, 32, "team_%s", CaptainName_T);	
		//Format(TeamName_CT, 32, "team_%s", CaptainName_CT);	
		if (!SwappedCheck())
		{
			PrintToChatAll("[\x04AUTOMIX\x01] Counter-Terrorists \x04[%d - %d]\x01 Terrorists", RoundsWon_CT, RoundsWon_T);
		}
		else if (SwappedCheck())
		{
			PrintToChatAll("[\x04AUTOMIX\x01] Counter-Terrorists \x04[%d - %d]\x01 Terrorists", RoundsWon_CT, RoundsWon_T);
		}
	}
	return Plugin_Handled;
}

public bool SwappedCheck()
{
	if (TeamsWereSwapped)
	{
		return true;
	}
	return false;
}

public bool CanUseStay()
{
	if (StayUsed)
	{
		return false;
	}
	return true;
}

public bool CanUseSwitch()
{
	if (SwitchUsed)
	{
		return false;
	}
	return true;
}

public bool ClientCheckFunction(client)
{
	GetClientAuthId(client, AuthId_Steam2, ClientCheck, 32, false);
	if (StrEqual(ClientCheck, CaptainID_CT, false))
	{
		return true;
	}
	else if (StrEqual(ClientCheck, CaptainID_T, false))
	{
		return true;
	}
	return false;
}

public bool CaptainCheck(client)
{
	if (ClientCheckFunction(client))
	{
		return true;
	}
	return false;
}

public void ResetValues()
{
	StayUsed = false;
	SwitchUsed = false;
	TeamsWereSwapped = false;
}

public Action WinningKnifeRoundTeam()
{
	KRWinner = CS_TEAM_NONE;
	team_t = GetAlivePlayersCount(CS_TEAM_T);
	team_ct = GetAlivePlayersCount(CS_TEAM_CT);
	if (team_t > team_ct)
	{
		KRWinner = CS_TEAM_T;
	}
	else if (team_ct > team_t)
	{
		KRWinner = CS_TEAM_CT;
	}
	return Plugin_Handled;
}

public int RandomCaptainCT()
{
	int PlayersCT[MAXPLAYERS + 1];
	int PlayersCountCT;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (GetClientTeam(i) == CS_TEAM_CT)
			{
				PlayersCT[PlayersCountCT++] = i;
			}
		}
	}
	return PlayersCT[GetRandomInt(0, PlayersCountCT - 1)];
}

public int RandomCaptainT()
{
	int PlayersT[MAXPLAYERS + 1];
	int PlayersCountT;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (GetClientTeam(i) == CS_TEAM_T)
			{
				PlayersT[PlayersCountT++] = i;
			}
		}
	}
	return PlayersT[GetRandomInt(0, PlayersCountT - 1)];
}

public Action GetCaptainCT(client, args)
{
	CaptainCT = RandomCaptainCT();
	GetClientName(CaptainCT, CaptainName_CT, 32);
	GetClientAuthId(CaptainCT, AuthId_Steam2, CaptainID_CT, 32, false);
	PrintToChatAll("[\x04AUTOMIX\x01] Capitan de lado CT: \x04%s", CaptainName_CT);
}

public Action GetCaptainT(client, args)
{
	CaptainT = RandomCaptainT();
	GetClientName(CaptainT, CaptainName_T, 32);
	GetClientAuthId(CaptainT, AuthId_Steam2, CaptainID_T, 32, false);
	CaptainsSelected = true;
	PrintToChatAll("[\x04AUTOMIX\x01] Capitan de lado T: \x04%s", CaptainName_T);
}

//Code by Leonardo
GetAlivePlayersCount(iTeam)
{
	int iCount, i; iCount = 0;
	
	for (i = 1; i <= MaxClients; i++)
	if (IsClientValid(i) && IsPlayerAlive(i) && GetClientTeam(i) == iTeam)
		iCount++;
	
	return iCount;
}

//Code by Antithasys
stock PrintToAdmins(const char message[64], const char flags[32])
{
	for (new x = 1; x <= MaxClients; x++)
	{
		if (IsClientValid(x) && IsValidAdmin(x, flags))
		{
			PrintToChat(x, message);
		}
	}
}

stock bool IsClientValid(int client)
{
	if (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client))
		return true;
	return false;
}

public bool ClientTeamValid(client)
{
	int ClientTeam = GetClientTeam(client);
	if (ClientTeam != CS_TEAM_CT && ClientTeam != CS_TEAM_T)
	{
		return false;
	}
	return true;
}

//Code by Antithasys
stock bool IsValidAdmin(client, const char flags[32])
{
	int ibFlags = ReadFlagString(flags);
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags)
	{
		return true;
	}
	if (GetUserFlagBits(client) & ADMFLAG_GENERIC)
	{
		return true;
	}
	return false;
}

//Code by X@IDER
ChangeClientTeamEx(client, team)
{
	if ((game != GAME_CSTRIKE) || (team < TEAM1))
	{
		ChangeClientTeam(client, team);
		return;
	}
	
	int oldTeam = GetClientTeam(client);
	CS_SwitchTeam(client, team);
	if (!IsPlayerAlive(client))return;
	
	char model[PLATFORM_MAX_PATH];
	char newmodel[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	newmodel = model;
	
	if (oldTeam == TEAM1)
	{
		int c4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
		if (c4 != -1)DropWeapon(client, c4);
		
		if (StrContains(model, t_models[0], false))newmodel = ct_models[0];
		if (StrContains(model, t_models[1], false))newmodel = ct_models[1];
		if (StrContains(model, t_models[2], false))newmodel = ct_models[2];
		if (StrContains(model, t_models[3], false))newmodel = ct_models[3];
	} else
		if (oldTeam == TEAM2)
	{
		SetEntProp(client, Prop_Send, "m_bHasDefuser", 0, 1);
		
		if (StrContains(model, ct_models[0], false))newmodel = t_models[0];
		if (StrContains(model, ct_models[1], false))newmodel = t_models[1];
		if (StrContains(model, ct_models[2], false))newmodel = t_models[2];
		if (StrContains(model, ct_models[3], false))newmodel = t_models[3];
	}
	
	if (hSetModel != INVALID_HANDLE)SDKCall(hSetModel, client, newmodel);
}
//Code by X@IDER
SwapPlayer(client, target)
{
	switch (GetClientTeam(target))
	{
		case TEAM1 : ChangeClientTeamEx(target, TEAM2);
		case TEAM2 : ChangeClientTeamEx(target, TEAM1);
		default:
		return;
	}
}
//Code by X@IDER
public Action Command_Swap(client, args)
{
	if (!args)
	{
		ReplyToCommand(client, "[\x04AUTOMIX\x01] smpadmin_swap <target>");
		return Plugin_Handled;
	}
	char pattern[MAX_NAME];
	GetCmdArg(1, pattern, sizeof(pattern));
	
	int cl = FindTarget(client, pattern);
	
	if (cl != -1)
		SwapPlayer(client, cl);
	else
		ReplyToCommand(client, "No target");
	
	return Plugin_Handled;
}

public SwapMenu(client)
{
	Handle menu = CreateMenu(MenuHandler_SwapMenu);
	SetMenuTitle(menu, "%T", "Swap Menu", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_SwapMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Swap Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			char selection_Name[40];
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selection_Name, sizeof(selection_Name));
			ServerCommand("smpadmin_swap %s", selection_Name);
			AdminMenuSMP(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

//Code by splewis
stock void ReplaceStringWithInt(char[] buffer, int len, const char[] replace, 
	int value, bool caseSensitive = false) {
	char intString[16];
	IntToString(value, intString, sizeof(intString));
	ReplaceString(buffer, len, replace, intString, caseSensitive);
}
//Code by X@IDER
public Action Command_Exchange(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[\x04AUTOMIX\x01] smpadmin_exchange <target1> <target2>");
		return Plugin_Handled;
	}
	
	char p1[MAX_NAME];
	char p2[MAX_NAME];
	GetCmdArg(1, p1, sizeof(p1));
	GetCmdArg(2, p2, sizeof(p2));
	
	int cl1 = FindTarget(client, p1);
	int cl2 = FindTarget(client, p2);
	
	if (cl1 == -1)ReplyToCommand(client, "No target");
	if (cl2 == -1)ReplyToCommand(client, "No target");
	
	if ((cl1 > 0) && (cl2 > 0))ExchangePlayers(client, cl1, cl2);
	
	return Plugin_Handled;
}

public ExchangePlayersMenu(client)
{
	Handle menu = CreateMenu(MenuHandler_ExchangePlayersMenu);
	SetMenuTitle(menu, "%T", "Exchange Players Menu", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_ExchangePlayersMenu(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Exchange Players Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global_exchange, sizeof(selected_player_global_exchange));
			ExchangePlayersMenu_ExchangeWith(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public ExchangePlayersMenu_ExchangeWith(client)
{
	Handle menu = CreateMenu(MenuHandler_ExchangePlayersMenu_ExchangeWith);
	SetMenuTitle(menu, "%T", "Exchange Players With Menu", LANG_SERVER);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))
			continue;
		
		char ClientUserID[40];
		int ClientID = GetClientUserId(i);
		IntToString(ClientID, ClientUserID, sizeof(ClientUserID));
		char ClientName[40];
		GetClientName(i, ClientName, sizeof(ClientName));
		AddMenuItem(menu, ClientUserID, ClientName);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_ExchangePlayersMenu_ExchangeWith(Handle menu, MenuAction action, param1, param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Exchange Players With Menu", param1);
			
			Handle panel = view_as<Handle>(param2);
			SetPanelTitle(panel, buffer);
		}
		
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			int selection_UserID = GetClientOfUserId(StringToInt(info));
			GetClientName(selection_UserID, selected_player_global_exchange_with, sizeof(selected_player_global_exchange_with));
			ServerCommand("smpadmin_exchange %s %s", selected_player_global_exchange, selected_player_global_exchange_with);
			AdminMenuSMP(param1);
		}
		
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

//Code by X@IDER
public Action Command_TeamSwap(client, args)
{
	for (new i = 1; i <= MaxClients; i++)
	if (IsClientInGame(i))switch (GetClientTeam(i))
	{
		case TEAM1 : ChangeClientTeamEx(i, TEAM2);
		case TEAM2 : ChangeClientTeamEx(i, TEAM1);
	}
	int ts = GetTeamScore(TEAM1);
	SetTeamScore(TEAM1, GetTeamScore(TEAM2));
	SetTeamScore(TEAM2, ts);
	PrintToChatAll("[\x04AUTOMIX\x01] \x01Se han intercambiado de equipos.");
	if (g_bLog)LogAction(client, -1, "\"%L\" swapped teams", client);
	return Plugin_Handled;
}

public Action PluginVersionSMP(client, args)
{
	PrintToChat(client, "[\x04AUTOMIX\x01] Version 1.0 complemento creado por \x07automaric");
	return Plugin_Handled;
}

public Action KickBotsSMP(client, args)
{
	ServerCommand("bot_kick");
	PrintToChat(client, "[\x04AUTOMIX\x01] Sacar a todos los bots...");
	return Plugin_Handled;
}

public void ResetTeamPausesFunction()
{
	TotalPausesCT = 0;
	TotalPausesT = 0;
}

public Action ResetTeamPausesSMP(client, args)
{
	ResetTeamPausesFunction();
	PrintToChat(client, "[\x04AUTOMIX\x01] El recuento de pausas del equipo se ha restablecido!");
	return Plugin_Handled;
}

public Action ShowPausesUsedSMP(client, args)
{
	int TacticPauseTeam = GetClientTeam(client);
	int MaxPausesPerTeam = SetMaxPausesPerTeamSMP.IntValue;
	MaxPausesCT = MaxPausesPerTeam;
	MaxPausesT = MaxPausesPerTeam;
	if (TacticPauseTeam == CS_TEAM_CT)
	{
		if (MaxPausesPerTeam > TotalPausesCT)
		{
			PrintToChat(client, "[\x04AUTOMIX\x01] Pausas del equipo utilizadas: %d fuera de %d.", TotalPausesCT, MaxPausesCT);
		}
		
		else if (MaxPausesPerTeam <= TotalPausesCT)
		{
			PrintToChat(client, "[\x04AUTOMIX\x01] Pausas del equipo utilizadas: %d fuera de %d (MAX).", TotalPausesCT, MaxPausesCT);
		}
		return Plugin_Handled;
	}
	
	if (TacticPauseTeam == CS_TEAM_T)
	{
		if (MaxPausesPerTeam > TotalPausesT)
		{
			PrintToChat(client, "[\x04AUTOMIX\x01] Pausas del equipo utilizadas: %d fuera de %d.", TotalPausesT, MaxPausesT);
		}
		
		else if (MaxPausesPerTeam <= TotalPausesT)
		{
			PrintToChat(client, "[\x04AUTOMIX\x01] Pausas del equipo utilizadas: %d fuera de %d (MAX).", TotalPausesT, MaxPausesT);
		}
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action TacticPauseSMP(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (IsPaused() || !IsClientValid(client))
		{
			return Plugin_Handled;
		}
		TacticUnpauseCT = false;
		TacticUnpauseT = false;
		int TacticPauseTeam = GetClientTeam(client);
		int MaxPausesPerTeam = SetMaxPausesPerTeamSMP.IntValue;
		if (SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_CT);
			Format(TeamName_CT, 32, "team_%s", CaptainName_T);
		}
		else if (!SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_T);
			Format(TeamName_CT, 32, "team_%s", CaptainName_CT);
		}
		if (TacticPauseTeam == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				if (!PausesLimitReachedCT())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] Timeout en freezetime llamado por %s", CaptainName_CT);
					ServerCommand("mp_pause_match");
					TotalPausesCT++;
					return Plugin_Handled;
				}
				else if (TotalPausesCT == MaxPausesPerTeam)
				{
					PrintToChat(client, "[\x04AUTOMIX\x01] No se puede pausar se alcanzo el limite permitido");
					return Plugin_Handled;
				}
				return Plugin_Handled;
			}
			PrintToChat(client, "[\x04AUTOMIX\x01] No tenes permitido pedir \x04.pause");
		}
		else if (TacticPauseTeam == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				if (!PausesLimitReachedT())
				{
					PrintToChatAll("[\x04AUTOMIX\x01] Timeout en freezetime llamado por %s", CaptainName_T);
					ServerCommand("mp_pause_match");
					TotalPausesT++;
					return Plugin_Handled;
				}
				else if (TotalPausesT == MaxPausesPerTeam)
				{
					PrintToChat(client, "[\x04AUTOMIX\x01] No se puede pausar se alcanzo el limite permitido");
					return Plugin_Handled;
				}
				return Plugin_Handled;
			}
			PrintToChat(client, "[\x04AUTOMIX\x01] No tenes permitido pedir \x01.pause");
		}
		return Plugin_Handled;
	}
	PrintToChat(client, "[\x04AUTOMIX\x01] Solo podes pausar durante el match.");
	return Plugin_Handled;
}

public Action ForcePauseSMP(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (IsPaused())
		{
			return Plugin_Handled;
		}
		ServerCommand("mp_pause_match");
		PrintToChatAll("[\x04AUTOMIX\x01] El match se pausara durante el tiempo libre.");
		return Plugin_Handled;
	}
	PrintToChat(client, "[\x04AUTOMIX\x01] Solo podes pausar durante el match.");
	return Plugin_Handled;
}

public Action TacticUnpauseSMP(client, args)
{
	if (CurrentRound == MATCH)
	{
		if (!IsPaused() || !IsClientValid(client))
		{
			return Plugin_Handled;
		}
		int team = GetClientTeam(client);
		if (SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_CT);
			Format(TeamName_CT, 32, "team_%s", CaptainName_T);
		}
		else if (!SwappedCheck())
		{
			Format(TeamName_T, 32, "team_%s", CaptainName_T);
			Format(TeamName_CT, 32, "team_%s", CaptainName_CT);
		}
		if (team == CS_TEAM_CT)
		{
			if (CaptainCheck(client))
			{
				TacticUnpauseCT = true;
			}
		}
		else if (team == CS_TEAM_T)
		{
			if (CaptainCheck(client))
			{
				TacticUnpauseT = true;
			}
		}
		if (TacticUnpauseCT && TacticUnpauseT)
		{
			ServerCommand("mp_unpause_match");
			UnpauseLock = false;
			return Plugin_Handled;
		}
		else if (TacticUnpauseCT && !TacticUnpauseT && !UnpauseLock)
		{
			PrintToChatAll("[\x04AUTOMIX\x01] \x04%s \x01Escribio .unpause! Esperando que \x04%s \x01escriba \x04!unpause", CaptainName_CT, CaptainName_T);
			UnpauseLock = true;
			return Plugin_Handled;
		}
		else if (!TacticUnpauseCT && TacticUnpauseT && !UnpauseLock)
		{
			PrintToChatAll("[\x04AUTOMIX\x01] \x04%s \x01Escribio .unpause! Esperando que \x04%s \x01escriba \x04!unpause", CaptainName_T, CaptainName_CT);
			UnpauseLock = true;
			return Plugin_Handled;
		}
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action ForceUnPauseSMP(client, args)
{
	if (!IsPaused())
	{
		return Plugin_Handled;
	}
	ServerCommand("mp_unpause_match");
	PrintToChatAll("[\x04AUTOMIX\x01] El match se ha reanudado.");
	return Plugin_Handled;
}

public Action Ladder5on5SMP(client, cfg)
{
	ServerCommand("mp_ct_default_secondary weapon_hkp2000");
	ServerCommand("mp_t_default_secondary weapon_glock");
	ServerCommand("mp_give_player_c4 1");
	ServerCommand("ammo_grenade_limit_default 1");
	ServerCommand("ammo_grenade_limit_flashbang 2");
	ServerCommand("ammo_grenade_limit_total 4");
	ServerCommand("bot_quota 0");
	ServerCommand("cash_player_bomb_defused 300");
	ServerCommand("cash_player_bomb_planted 300");
	ServerCommand("cash_player_damage_hostage -30");
	ServerCommand("cash_player_interact_with_hostage 150");
	ServerCommand("cash_player_killed_enemy_default 300");
	ServerCommand("cash_player_killed_enemy_factor 1");
	ServerCommand("cash_player_killed_hostage -1000");
	ServerCommand("cash_player_killed_teammate -300");
	ServerCommand("cash_player_rescued_hostage 1000");
	ServerCommand("cash_team_elimination_bomb_map 3250");
	ServerCommand("cash_team_hostage_alive 150");
	ServerCommand("cash_team_hostage_interaction 150");
	ServerCommand("cash_team_loser_bonus 1400");
	ServerCommand("cash_team_loser_bonus_consecutive_rounds 500");
	ServerCommand("cash_team_planted_bomb_but_defused 800");
	ServerCommand("cash_team_rescued_hostage 750");
	ServerCommand("cash_team_terrorist_win_bomb 3500");
	ServerCommand("cash_team_win_by_defusing_bomb 3500");
	ServerCommand("cash_team_win_by_hostage_rescue 3500");
	ServerCommand("cash_player_get_killed 0");
	ServerCommand("cash_player_respawn_amount 0");
	ServerCommand("cash_team_elimination_hostage_map_ct 2000");
	ServerCommand("cash_team_elimination_hostage_map_t 1000");
	ServerCommand("cash_team_win_by_time_running_out_bomb 3250");
	ServerCommand("cash_team_win_by_time_running_out_hostage 3250");
	ServerCommand("ff_damage_reduction_grenade 0.85");
	ServerCommand("ff_damage_reduction_bullets 0.33");
	ServerCommand("ff_damage_reduction_other 0.4");
	ServerCommand("ff_damage_reduction_grenade_self 1");
	ServerCommand("mp_afterroundmoney 0");
	ServerCommand("mp_autokick 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_buytime 15");
	ServerCommand("mp_c4timer 40");
	ServerCommand("mp_death_drop_defuser 1");
	ServerCommand("mp_death_drop_grenade 2");
	ServerCommand("mp_death_drop_gun 1");
	ServerCommand("mp_defuser_allocation 0");
	ServerCommand("mp_do_warmup_period 1");
	ServerCommand("mp_forcecamera 1");
	ServerCommand("mp_force_pick_time 160");
	ServerCommand("mp_free_armor 0");
	ServerCommand("mp_freezetime 12");
	ServerCommand("mp_friendlyfire 1");
	ServerCommand("mp_halftime 1");
	ServerCommand("mp_halftime_duration 30");
	ServerCommand("mp_join_grace_time 30");
	ServerCommand("mp_limitteams 0 ");
	ServerCommand("mp_logdetail 3");
	ServerCommand("mp_match_can_clinch 1");
	ServerCommand("mp_match_end_restart 1");
	ServerCommand("mp_maxmoney 16000");
	ServerCommand("mp_maxrounds 30");
	ServerCommand("mp_molotovusedelay 0");
	ServerCommand("mp_overtime_enable 1");
	ServerCommand("mp_overtime_maxrounds 10");
	ServerCommand("mp_overtime_startmoney 16000");
	ServerCommand("mp_playercashawards 1");
	ServerCommand("mp_playerid 0");
	ServerCommand("mp_playerid_delay 0.5");
	ServerCommand("mp_playerid_hold 0.25");
	ServerCommand("mp_round_restart_delay 5");
	ServerCommand("mp_roundtime 1.92");
	ServerCommand("mp_roundtime_defuse 1.92");
	ServerCommand("mp_solid_teammates 1");
	ServerCommand("mp_startmoney 800");
	ServerCommand("mp_teamcashawards 1");
	ServerCommand("mp_timelimit 0");
	ServerCommand("mp_tkpunish 0");
	ServerCommand("mp_warmuptime 1");
	ServerCommand("mp_weapons_allow_map_placed 1");
	ServerCommand("mp_weapons_allow_zeus 1");
	ServerCommand("mp_win_panel_display_time 15");
	ServerCommand("spec_freeze_time 2.0");
	ServerCommand("spec_freeze_panel_extended_time 0");
	ServerCommand("spec_freeze_time_lock 2");
	ServerCommand("spec_freeze_deathanim_time 0");
	ServerCommand("sv_accelerate 5.5");
	ServerCommand("sv_stopspeed 80");
	ServerCommand("sv_allow_votes 0");
	ServerCommand("sv_allow_wait_command 0");
	ServerCommand("sv_alltalk 0");
	ServerCommand("sv_alternateticks 0");
	ServerCommand("sv_cheats 0");
	ServerCommand("sv_clockcorrection_msecs 15");
	ServerCommand("sv_consistency 0");
	ServerCommand("sv_contact 0");
	ServerCommand("sv_damage_print_enable 0");
	ServerCommand("sv_dc_friends_reqd 0");
	ServerCommand("sv_deadtalk 1");
	ServerCommand("sv_forcepreload 0");
	ServerCommand("sv_friction 5.2");
	ServerCommand("sv_full_alltalk 0");
	ServerCommand("sv_gameinstructor_disable 1");
	ServerCommand("sv_ignoregrenaderadio 0 ");
	ServerCommand("sv_kick_players_with_cooldown 0");
	ServerCommand("sv_kick_ban_duration 0");
	ServerCommand("sv_lan 0");
	ServerCommand("sv_log_onefile 0");
	ServerCommand("sv_logbans 1");
	ServerCommand("sv_logecho 1");
	ServerCommand("sv_logfile 1");
	ServerCommand("sv_logflush 0");
	ServerCommand("sv_logsdir logfiles");
	ServerCommand("sv_maxrate 0");
	ServerCommand("sv_mincmdrate 30");
	ServerCommand("sv_minrate 20000");
	ServerCommand("sv_competitive_minspec 1");
	ServerCommand("sv_competitive_official_5v5 1");
	ServerCommand("sv_pausable 1");
	ServerCommand("sv_pure 1");
	ServerCommand("sv_pure_kick_clients 1");
	ServerCommand("sv_pure_trace 0");
	ServerCommand("sv_spawn_afk_bomb_drop_time 30");
	ServerCommand("sv_steamgroup_exclusive 0");
	ServerCommand("sv_voiceenable 1");
	ServerCommand("sv_auto_full_alltalk_during_warmup_half_end 0");
	ServerCommand("mp_restartgame 1");
	ResetTeamPausesFunction();
	CreateTimer(4.0, MatchMessage);
	return Plugin_Handled;
}

public Action LoadConfigWarmup(client, cfg)
{
	ServerCommand("mp_ct_default_secondary weapon_hkp2000");
	ServerCommand("mp_t_default_secondary weapon_glock");
	ServerCommand("ammo_grenade_limit_default 0");
	ServerCommand("ammo_grenade_limit_flashbang 0");
	ServerCommand("ammo_grenade_limit_total 0");
	ServerCommand("bot_quota 0");
	ServerCommand("cash_player_bomb_defused 300");
	ServerCommand("cash_player_bomb_planted 300");
	ServerCommand("cash_player_damage_hostage -30");
	ServerCommand("cash_player_interact_with_hostage 150");
	ServerCommand("cash_player_killed_enemy_default 300");
	ServerCommand("cash_player_killed_enemy_factor 1");
	ServerCommand("cash_player_killed_hostage -1000");
	ServerCommand("cash_player_killed_teammate -300");
	ServerCommand("cash_player_rescued_hostage 1000");
	ServerCommand("cash_team_elimination_bomb_map 3250");
	ServerCommand("cash_team_hostage_alive 150");
	ServerCommand("cash_team_hostage_interaction 150");
	ServerCommand("cash_team_loser_bonus 1400");
	ServerCommand("cash_team_loser_bonus_consecutive_rounds 500");
	ServerCommand("cash_team_planted_bomb_but_defused 800");
	ServerCommand("cash_team_rescued_hostage 750");
	ServerCommand("cash_team_terrorist_win_bomb 3500");
	ServerCommand("cash_team_win_by_defusing_bomb 3500");
	ServerCommand("cash_team_win_by_hostage_rescue 3500");
	ServerCommand("cash_player_get_killed 0");
	ServerCommand("cash_player_respawn_amount 0");
	ServerCommand("cash_team_elimination_hostage_map_ct 2000");
	ServerCommand("cash_team_elimination_hostage_map_t 1000");
	ServerCommand("cash_team_win_by_time_running_out_bomb 3250");
	ServerCommand("cash_team_win_by_time_running_out_hostage 3250");
	ServerCommand("ff_damage_reduction_grenade 0.85");
	ServerCommand("ff_damage_reduction_bullets 0.33");
	ServerCommand("ff_damage_reduction_other 0.4");
	ServerCommand("ff_damage_reduction_grenade_self 1");
	ServerCommand("mp_afterroundmoney 0");
	ServerCommand("mp_autokick 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_buytime 15");
	ServerCommand("mp_c4timer 35");
	ServerCommand("mp_death_drop_defuser 1");
	ServerCommand("mp_death_drop_grenade 2");
	ServerCommand("mp_death_drop_gun 1");
	ServerCommand("mp_defuser_allocation 0");
	ServerCommand("mp_do_warmup_period 1");
	ServerCommand("mp_forcecamera 1");
	ServerCommand("mp_force_pick_time 160");
	ServerCommand("mp_free_armor 0");
	ServerCommand("mp_freezetime 6");
	ServerCommand("mp_friendlyfire 0");
	ServerCommand("mp_halftime 0");
	ServerCommand("mp_halftime_duration 0");
	ServerCommand("mp_join_grace_time 30");
	ServerCommand("mp_limitteams 0");
	ServerCommand("mp_logdetail 3");
	ServerCommand("mp_match_can_clinch 1");
	ServerCommand("mp_match_end_restart 1");
	ServerCommand("mp_maxmoney 9999999");
	ServerCommand("mp_maxrounds 5");
	ServerCommand("mp_molotovusedelay 0");
	ServerCommand("mp_overtime_enable 1");
	ServerCommand("mp_overtime_maxrounds 10");
	ServerCommand("mp_overtime_startmoney 16000");
	ServerCommand("mp_playercashawards 1");
	ServerCommand("mp_playerid 0");
	ServerCommand("mp_playerid_delay 0.5");
	ServerCommand("mp_playerid_hold 0.25");
	ServerCommand("mp_round_restart_delay 5");
	ServerCommand("mp_roundtime 10");
	ServerCommand("mp_roundtime_defuse 10");
	ServerCommand("mp_solid_teammates 1");
	ServerCommand("mp_startmoney 9999999");
	ServerCommand("mp_teamcashawards 1");
	ServerCommand("mp_timelimit 0");
	ServerCommand("mp_tkpunish 0");
	ServerCommand("mp_warmuptime 36000");
	ServerCommand("mp_weapons_allow_map_placed 1");
	ServerCommand("mp_weapons_allow_zeus 1");
	ServerCommand("mp_win_panel_display_time 15");
	ServerCommand("spec_freeze_time 5.0");
	ServerCommand("spec_freeze_panel_extended_time 0");
	ServerCommand("sv_accelerate 5.5");
	ServerCommand("sv_stopspeed 80");
	ServerCommand("sv_allow_votes 0");
	ServerCommand("sv_allow_wait_command 0");
	ServerCommand("sv_alltalk 1");
	ServerCommand("sv_alternateticks 0");
	ServerCommand("sv_cheats 0");
	ServerCommand("sv_clockcorrection_msecs 15");
	ServerCommand("sv_consistency 0");
	ServerCommand("sv_contact 0");
	ServerCommand("sv_damage_print_enable 0");
	ServerCommand("sv_dc_friends_reqd 0");
	ServerCommand("sv_deadtalk 1");
	ServerCommand("sv_forcepreload 0");
	ServerCommand("sv_friction 5.2");
	ServerCommand("sv_full_alltalk 0");
	ServerCommand("sv_gameinstructor_disable 1");
	ServerCommand("sv_ignoregrenaderadio 0");
	ServerCommand("sv_kick_players_with_cooldown 0");
	ServerCommand("sv_kick_ban_duration 0 ");
	ServerCommand("sv_lan 0");
	ServerCommand("sv_log_onefile 0");
	ServerCommand("sv_logbans 1");
	ServerCommand("sv_logecho 1");
	ServerCommand("sv_logfile 1");
	ServerCommand("sv_logflush 0");
	ServerCommand("sv_logsdir logfiles");
	ServerCommand("sv_maxrate 0");
	ServerCommand("sv_mincmdrate 30");
	ServerCommand("sv_minrate 20000");
	ServerCommand("sv_competitive_minspec 1");
	ServerCommand("sv_competitive_official_5v5 1");
	ServerCommand("sv_pausable 1");
	ServerCommand("sv_pure 1");
	ServerCommand("sv_pure_kick_clients 1");
	ServerCommand("sv_pure_trace 0");
	ServerCommand("sv_spawn_afk_bomb_drop_time 30");
	ServerCommand("sv_steamgroup_exclusive 0");
	ServerCommand("sv_voiceenable 1");
	ServerCommand("mp_restartgame 1");
	ServerCommand("mp_warmup_start");
	ResetValues();
	ResetTeamPausesFunction();
	CurrentRound = WARMUP;
	ReadyPlayers = 0;
	ManualCaptain = false;
	CaptainMenu = false;
	ClearArray(PlayersReadyList);
	CreateTimer(2.0, WarmupLoadedSMP);
	return Plugin_Handled;
}

public bool ManualCaptainCheck()
{
	if (ManualCaptain)
	{
		return true;
	}
	return false;
}

public bool CaptainsSelectedCheck()
{
	if (CaptainsSelected)
	{
		return true;
	}
	return false;
}

public bool CaptainMenuCheck()
{
	if (CaptainMenu)
	{
		return true;
	}
	return false;
}

public Action KnifeRoundRandom(client, cfg)
{
	CurrentRound = KNIFE_ROUND;
	ServerCommand("mp_unpause_match");
	ServerCommand("mp_warmuptime 1");
	ServerCommand("mp_ct_default_secondary none");
	ServerCommand("mp_t_default_secondary none");
	ServerCommand("mp_free_armor 1");
	ServerCommand("mp_roundtime 60");
	ServerCommand("mp_round_restart_delay 5");
	ServerCommand("mp_roundtime_defuse 60");
	ServerCommand("mp_roundtime_hostage 60");
	ServerCommand("mp_give_player_c4 0");
	ServerCommand("mp_maxmoney 0");
	ServerCommand("mp_restartgame 1");
	ResetTeamPausesFunction();
	ResetValues();
	ServerCommand("smpadmin_getcaptain_t");
	ServerCommand("smpadmin_getcaptain_ct");
	CreateTimer(2.0, KnifeRoundMessage);
	return Plugin_Handled;
}

public Action LoadConfigKnifeRound(client, cfg)
{
	if (CaptainMenuCheck())
	{
		if (!ManualCaptainCheck())
		{
			ServerCommand("mp_unpause_match");
			ServerCommand("mp_warmuptime 1");
			ServerCommand("mp_ct_default_secondary none");
			ServerCommand("mp_t_default_secondary none");
			ServerCommand("mp_free_armor 1");
			ServerCommand("mp_roundtime 60");
			ServerCommand("mp_round_restart_delay 5");
			ServerCommand("mp_roundtime_defuse 60");
			ServerCommand("mp_roundtime_hostage 60");
			ServerCommand("mp_give_player_c4 0");
			ServerCommand("mp_maxmoney 0");
			ServerCommand("mp_restartgame 1");
			ResetTeamPausesFunction();
			ResetValues();
			ServerCommand("smpadmin_getcaptain_t");
			ServerCommand("smpadmin_getcaptain_ct");
			CreateTimer(2.0, KnifeRoundMessage);
			CurrentRound = KNIFE_ROUND;
			return Plugin_Handled;
		}
		else if (ManualCaptainCheck())
		{
			if (!CaptainsSelectedCheck())
			{
				CT_ChooseCaptainForAdmin(client);
				return Plugin_Handled;
			}
			else if (CaptainsSelectedCheck())
			{
				ServerCommand("mp_unpause_match");
				ServerCommand("mp_warmuptime 1");
				ServerCommand("mp_ct_default_secondary none");
				ServerCommand("mp_t_default_secondary none");
				ServerCommand("mp_free_armor 1");
				ServerCommand("mp_roundtime 60");
				ServerCommand("mp_round_restart_delay 5");
				ServerCommand("mp_roundtime_defuse 60");
				ServerCommand("mp_roundtime_hostage 60");
				ServerCommand("mp_give_player_c4 0");
				ServerCommand("mp_maxmoney 0");
				ServerCommand("mp_restartgame 1");
				ResetTeamPausesFunction();
				ResetValues();
				CreateTimer(2.0, KnifeRoundMessage);
				CurrentRound = KNIFE_ROUND;
				return Plugin_Handled;
			}
			return Plugin_Handled;
		}
		return Plugin_Handled;
	}
	
	if (!CaptainMenuCheck())
	{
		CaptainMenuForAdmin(client);
	}
	return Plugin_Handled;
}

public Action PluginHelpCvarsSMP(client, cfg)
{
	PrintToConsole(client, "[\x04AUTOMIX\x01] sm_cvar smp_set_pause_limit NUMBER \x04-> \x01establacer el limite de pausas permitidas por equipo");
	PrintToConsole(client, "[\x04AUTOMIX\x01] sm_cvar smp_ready_players_needed NUMBER \x04-> \x01establecer jugadores listo para comenzar la ronda de cuchillos");
	PrintToChat(client, "[\x04AUTOMIX\x01] Compruebe su consola para ver si hay cvars.");
	return Plugin_Handled;
}

public Action PluginHelpAdminSMP(client, cfg)
{
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin \x04-> \x01Menu de administracion de AUTOMIX: debe usar este");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_warmup \x04-> \x01iniciar el calentamiento");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_kniferound \x04-> \x01iniciar ronda de cuchillo");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_pause \x04-> \x01forzar pausa en tiempo libre");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_unpause \x04-> \x01forzar la reanudacion en tiempo libre");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_team_pauses_reset \x04-> \x01restablecer el recuento de pausas del equipo, usar al final de un match (si no hay cambio de mapa)");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_bot_kick \x07-> \x01sacar a todos los bots");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_help_cvars \x07-> \x01lista de cvars");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_swap \x07-> \x01intercambiar jugadores de equipo");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_teamswap \x07-> \x01intercambiar equipos");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_exchange \x07-> \x01intercambiar jugadores entre ellos");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_getcaptain_t \x07-> \x01consigue nuevo capitan para T");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smpadmin_getcaptain_ct \x07-> \x01consigue nuevo capitan para CT");
	PrintToChat(client, "[\x04AUTOMIX\x01] Compruebe su consola para los comandos de administrador.");
	return Plugin_Handled;
}

public Action PluginHelpSMP(client, cfg)
{
	PrintToConsole(client, "[\x04AUTOMIX\x01] smp_pause \x04-> \x01pedir una pause en tiempo libre");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smp_unpause \x04-> \x01anular la pause en tiempo libre");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smp_pauses_used \x04-> \x01mostrar la cantidad de pausas utilizadas");
	PrintToConsole(client, "[\x04AUTOMIX\x01] smp_version \x04-> \x01mostrar la version del plugin");
	PrintToChat(client, "[\x04AUTOMIX\x01] Revisa tu consola para ver los comandos del jugador.");
	return Plugin_Handled;
}

public Action WarmupLoadedSMP(Handle timer)
{
	PrintToChatAll("[\x04AUTOMIX\x01] Calentamiento");
}

public Action KnifeRoundMessage(Handle timer)
{
	PrintToChatAll("[\x04AUTOMIX\x01] \x04KNIFE");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04KNIFE");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04KNIFE");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04KNIFE");
	PrintToChatAll("[\x04AUTOMIX\x01] El equipo que gane podra elegir de que lado comenzar.");
}

public Action Ladder2on2Loaded(Handle timer)
{
	PrintToChatAll("[\x04AUTOMIX\x01] Configuracion 2V2 ESL cargada!");
}

public Action Ladder1on1Loaded(Handle timer)
{
	PrintToChatAll("[\x04AUTOMIX\x01] Configuracion 1V1 ESL cargada!");
}

public Action StartMatch(Handle timer)
{
	ServerCommand("smpadmin_match");
}

public Action Unpause(Handle timer)
{
	ServerCommand("mp_unpause_match");
}

public Action StartKnifeRound(Handle timer)
{
	ServerCommand("smpadmin_kniferound");
}

public Action MatchMessage(Handle timer)
{
	PrintToChatAll("[\x04AUTOMIX\x01] \x04LIVE!");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04LIVE!");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04LIVE!");
	PrintToChatAll("[\x04AUTOMIX\x01] \x04LIVE!");
	CurrentRound = MATCH;
}

public Action MatchEnd(Handle timer)
{
	ServerCommand("smpadmin_warmup");
}

public Action KnifeRoundRandomTimer(Handle timer)
{
	ServerCommand("smpadmin_kniferound_random");
}