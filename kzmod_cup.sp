#pragma semicolon 1

public Plugin:myinfo = 
{
    name = "KZmod Cup",
    author = "Aoki",
    description = "Cup administration plugin",
    version = "1.0",
    url = "http://www.kzmod.com/"
}

//-------------------------------------------------------------------------
// Includes
//-------------------------------------------------------------------------
#include <sourcemod>
#include <sdktools>

//-------------------------------------------------------------------------
// Defines 
//-------------------------------------------------------------------------
#define LOG_DEBUG_ENABLE 0
#define LOG_TO_CHAT 0
#define LOG_TO_SERVER 1

#define MENU_OPTION_SET     "set"
#define MENU_OPTION_POS     "pos"
#define MENU_OPTION_START  "start"
#define MENU_OPTION_CANCEL "end"
#define MENU_OPTION_NOCLIP "noclip"
#define MENU_OPTION_TIME    "time"
#define MENU_OPTION_TELE    "tele"
#define MENU_OPTION_1ST_PLACE "1st"
#define MENU_OPTION_2ND_PLACE "2nd"
#define MENU_OPTION_3RD_PLACE "3rd"
#define MENU_OPTION_SAY_WINNER "winner"
#define MENU_OPTION_SPEC "spec"

#define MENU_10MIN "10min"
#define MENU_5MIN  "5min"
#define MENU_3MIN  "3min"
#define MENU_2MIN  "2min"
#define MENU_1MIN  "1min"

#define TEAM_PLAYERS 0
//TODO: Fix bug when players are on elite team.

#define MAX_WINNERS 3
#define MAX_STRING_LEN 128
#define NUM_COUNT_SOUNDS 11
#define CUP_START_COUNTDOWN_SEC 11

#define IN_HOOK (1<<29)

//-------------------------------------------------------------------------
// Types 
//-------------------------------------------------------------------------

//-------------------------------------------------------------------------
// Globals 
//-------------------------------------------------------------------------
static gnCupAdminClientIndex = -1;
static Float:garStartPos[3];
static Float:garStartAngles[3];
static bool:geStartPosSet = false;
static Handle:ghCountdownTimer = INVALID_HANDLE;
static gnCupDurationSec = (5 * 60) + CUP_START_COUNTDOWN_SEC;
static Handle:ghCupMenu = INVALID_HANDLE;
static Handle:ghCupTimeSubMenu = INVALID_HANDLE;
static bool:geCupInProgress = false;
static gnCountDownSec = CUP_START_COUNTDOWN_SEC;
static gnTimeSec = 0;
static Handle:ghCupDurationCvar = INVALID_HANDLE;
static Handle:ghSoundPrecacheTrie = INVALID_HANDLE;
static bool:geAdminInMenu = false;
static String:gpanWinners[MAX_WINNERS][MAX_NAME_LENGTH];
static bool:ganAllowSpectateSwitch[MAXPLAYERS+1] = { false, ... };

static String:gaanTimeSounds[NUM_COUNT_SOUNDS][MAX_STRING_LEN] = 
{ 
	"soul/cuptimer/zero.wav", 
	"soul/cuptimer/one.wav", 
	"soul/cuptimer/two.wav",
	"soul/cuptimer/three.wav",
	"soul/cuptimer/four.wav",
	"soul/cuptimer/five.wav",
	"soul/cuptimer/six.wav",
	"soul/cuptimer/seven.wav",
	"soul/cuptimer/eight.wav",
	"soul/cuptimer/nine.wav",
	"soul/cuptimer/ten.wav"
};

//-------------------------------------------------------------------------
// Functions 
//-------------------------------------------------------------------------
public OnPluginStart()
{
	InitAdminMenu();
	RegAdminCmd("kzmod_cup",cbAdminMenu,ADMFLAG_KICK,"Cup menu");
	
	InitConVars();
	
	AddCommandListener(cbChangeTeam, "spectate"); 
	AddCommandListener(cbChangeTeam, "climb"); 
	
	RegConsoleCmd("sm_giveup", cbCupGiveup, "Give up when playing cup");
}

//Do not allow new players to start playing during a cup
public OnClientPutInServer(anClient)
{
	if(geCupInProgress == true)
	{
		ForceSpectate(anClient);
	}
}

public OnClientDisconnect_Post(anClient)
{
	if(anClient == gnCupAdminClientIndex)
	{
		gnCupAdminClientIndex = -1;
		geAdminInMenu = false;
	}
}

public OnMapStart()
{
	SetUpSoundPrecacheTrie();
	
	gnCupAdminClientIndex = -1;
	geStartPosSet = false;
	geCupInProgress = false;
	geAdminInMenu = false;
	CloseCountdownTimer();
}

public Action:cbCupGiveup(anClient, ahArgs)
{
	if(geCupInProgress == true)
	{
		decl String:ppanPlayerName[MAX_NAME_LENGTH];
		GetClientName(anClient,ppanPlayerName,MAX_NAME_LENGTH);
		PrintToChatAll("\x04[CUP]\x03 %s has given up.",ppanPlayerName);
		ForceSpectate(anClient);
	}
}

public Action:OnPlayerRunCmd(anClient, &apButtons, &apImpulse, Float:arVel[3], Float:arAngles[3], &apWeapon)
{
	//Do not allow the hook during cups unless it is the cup admin
	if(geCupInProgress == true && anClient != gnCupAdminClientIndex)
	{
		apButtons &= ~IN_HOOK;
	}
}

public LogDebug(const String:aapanFormat[], any:...)
{
#if LOG_DEBUG_ENABLE == 1
	decl String:ppanBuffer[512];
	
	VFormat(ppanBuffer, sizeof(ppanBuffer), aapanFormat, 2);
#if LOG_TO_CHAT == 1
	PrintToChatAll("%s", ppanBuffer);
#endif
#if LOG_TO_SERVER == 1
	PrintToServer("%s", ppanBuffer);
#endif
#endif
}

InitAdminMenu()
{
	ghCupMenu = CreateMenu(cbMenuHandler,MENU_ACTIONS_ALL);
	SetMenuTitle(ghCupMenu, "KZmod Cup Administration");
	AddMenuItem(ghCupMenu, MENU_OPTION_SET, "Set self as admin");
	AddMenuItem(ghCupMenu, MENU_OPTION_POS, "Set start position");
	AddMenuItem(ghCupMenu, MENU_OPTION_TIME, "Set cup duration");
	AddMenuItem(ghCupMenu, MENU_OPTION_START, "Start cup");
	AddMenuItem(ghCupMenu, MENU_OPTION_CANCEL, "Cancel cup");
	AddMenuItem(ghCupMenu, MENU_OPTION_NOCLIP, "Toggle noclip");
	AddMenuItem(ghCupMenu, MENU_OPTION_TELE, "Teleport to next player");
	AddMenuItem(ghCupMenu, MENU_OPTION_1ST_PLACE, "Set first place");
	AddMenuItem(ghCupMenu, MENU_OPTION_2ND_PLACE, "Set second place");
	AddMenuItem(ghCupMenu, MENU_OPTION_3RD_PLACE, "Set third place");
	AddMenuItem(ghCupMenu, MENU_OPTION_SAY_WINNER, "Declare winners");
	AddMenuItem(ghCupMenu, MENU_OPTION_SPEC, "Spectate players");
	
	ghCupTimeSubMenu = CreateMenu(cbTimeSubMenuHandler,MENU_ACTIONS_ALL);
	SetMenuTitle(ghCupTimeSubMenu, "Set cup time");
	AddMenuItem(ghCupTimeSubMenu, MENU_10MIN, "10 minutes");
	AddMenuItem(ghCupTimeSubMenu, MENU_5MIN, "5 minutes");
	AddMenuItem(ghCupTimeSubMenu, MENU_3MIN, "3 minutes");
	AddMenuItem(ghCupTimeSubMenu, MENU_2MIN, "2 minutes");
	AddMenuItem(ghCupTimeSubMenu, MENU_1MIN, "1 minute");
}

InitConVars()
{
	//Set up cup time con var
	ghCupDurationCvar = FindConVar("kz_cup_duration_sec");
	
	if(ghCupDurationCvar == INVALID_HANDLE)
	{
		ghCupDurationCvar = CreateConVar("kz_cup_duration_sec", "300", "Amount of time the cup runs for in seconds");
	}
	
	if(ghCupDurationCvar != INVALID_HANDLE)
	{
		HookConVarChange(ghCupDurationCvar, cbCupDurationChange);
	}
	else
	{
		LogDebug("Failed to create convar");
	}
	
	gnCupDurationSec = GetConVarInt(ghCupDurationCvar) + CUP_START_COUNTDOWN_SEC;
}

public Action:cbChangeTeam(anClient, const String:apanString[], anArgc)  
{ 
	//If cup in progress, do not allow team changes except for admin or new players joining
	if(geCupInProgress == true && anClient != gnCupAdminClientIndex &&
	   ganAllowSpectateSwitch[anClient] == false)
	{
		if(GetClientTeam(anClient) == TEAM_PLAYERS)
		{
			PrintToChat(anClient,"\x04[CUP]\x03 Say !giveup to forfeit the cup.");
		}
		else
		{
			PrintToChat(anClient,"\x04[CUP]\x03 Cup is in progress.  Team change not allowed.");
		}
		
		return Plugin_Handled; 
	}
	else if(ganAllowSpectateSwitch[anClient] == true)
	{
		ganAllowSpectateSwitch[anClient] = false;
	}
	
	return Plugin_Continue; 
} 

ForceSpectate(anClient)
{
	ganAllowSpectateSwitch[anClient] = true;
	ClientCommand(anClient,"spectate");
}

public cbCupDurationChange(Handle:ahConvar, const String:apanOldVal[], const String:apanNewVal[])
{
	gnCupDurationSec = StringToInt(apanNewVal) + CUP_START_COUNTDOWN_SEC;
}

public Action:cbAdminMenu(anClient, ahArgs)
{
	DisplayMenu(ghCupMenu, anClient, 0);
 	return Plugin_Handled;
}

public cbMenuHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	new String:lpanInfo[32];
	
	if(ahAction != MenuAction_End)
	{
		geAdminInMenu = true;
	}
	
	if(ahAction == MenuAction_Select)
	{
		//Use GetMenuItem so there is no question about menu item order
		GetMenuItem(ahMenu, anSelection, lpanInfo, sizeof(lpanInfo));
		
		if(strcmp(lpanInfo,MENU_OPTION_SET) == 0)
		{
			gnCupAdminClientIndex = anClient;
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_POS) == 0)
		{
			SetCupStartPos(anClient);
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_START) == 0)
		{
			StartCup();
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_CANCEL) == 0)
		{
			CancelCup();
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_NOCLIP) == 0)
		{
			ToggleNoclip(anClient);
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_TIME) == 0)
		{
			DisplayMenu(ghCupTimeSubMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_TELE) == 0)
		{
			TeleportAdminToNextClient();
			DisplayMenu(ghCupMenu, anClient, 0);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_1ST_PLACE) == 0)
		{
			DisplayWinnerSelectionMenu(0,anClient);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_2ND_PLACE) == 0)
		{
			DisplayWinnerSelectionMenu(1,anClient);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_3RD_PLACE) == 0)
		{
			DisplayWinnerSelectionMenu(2,anClient);
		}
		else if(strcmp(lpanInfo,MENU_OPTION_SAY_WINNER) == 0)
		{
			PrintWinnersToChat();
		}
		else if(strcmp(lpanInfo,MENU_OPTION_SPEC) == 0)
		{
			DisplaySpectateSelectionMenu(anClient);
		}
	}
	else if(ahAction == MenuAction_DrawItem)
	{
		new lnStyle;
		GetMenuItem(ahMenu, anSelection, lpanInfo, sizeof(lpanInfo), lnStyle);
		
		if(strcmp(lpanInfo,MENU_OPTION_SET) != 0 && gnCupAdminClientIndex == -1)
		{
			lnStyle = ITEMDRAW_DISABLED;
		}
		else if(strcmp(lpanInfo,MENU_OPTION_START) == 0 && 
		        (geStartPosSet == false || geCupInProgress == true))
		{
			lnStyle = ITEMDRAW_DISABLED;
		}
		else if(strcmp(lpanInfo,MENU_OPTION_CANCEL) == 0 && geCupInProgress == false)
		{
			lnStyle = ITEMDRAW_DISABLED;
		}
				
		return lnStyle;
	}
	else if(ahAction == MenuAction_Cancel)
	{
		geAdminInMenu = false;
	}
	else if (ahAction == MenuAction_End)
	{
		//Do nothing
	}
	
	return 0;
}

PrintWinnersToChat()
{
	decl String:ppanPlaceStrings[MAX_WINNERS][4] = { "1st", "2nd", "3rd" };
	
	for(new lnIndex=0;lnIndex<MAX_WINNERS;lnIndex++)
	{
		if(strcmp(gpanWinners[lnIndex],"") != 0)
		{
			PrintToChatAll("\x04[CUP]\x03 %s place: %s",ppanPlaceStrings[lnIndex],gpanWinners[lnIndex]);
		}
	}
}

AddPlayersToMenu(Handle:ahMenu)
{
	decl String:lpanPlayerName[MAX_NAME_LENGTH];
	new bool:leStatus = false;
	
	for(new lnClient=1;lnClient<MaxClients+1;lnClient++)
	{
		if(IsPlayerValid(lnClient))
		{
			leStatus = GetClientName(lnClient, lpanPlayerName, sizeof(lpanPlayerName));
		
			if(leStatus && GetClientTeam(lnClient) == TEAM_PLAYERS)
			{
				AddMenuItem(ahMenu, lpanPlayerName, lpanPlayerName);
			}
		}
	}
}

DisplaySpectateSelectionMenu(anClient)
{
	new Handle:lhMenu = CreateMenu(cbSpectatePlayer,MENU_ACTIONS_ALL);
	SetMenuTitle(lhMenu, "Spectate player");
	AddPlayersToMenu(lhMenu);
	DisplayMenu(lhMenu,anClient,0);
}

public cbSpectatePlayer(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	decl String:ppanMenuName[MAX_NAME_LENGTH];
	decl String:ppanPlayerName[MAX_NAME_LENGTH];
	
	if(ahAction != MenuAction_End)
	{
		geAdminInMenu = true;
	}
	
	if(ahAction == MenuAction_Select)
	{
		GetMenuItem(ahMenu, anSelection, ppanMenuName, MAX_NAME_LENGTH);
		
		for(new lnClient=1;lnClient<MaxClients;lnClient++)
		{
			if(IsPlayerValid(lnClient))
			{
				GetClientName(lnClient,ppanPlayerName,MAX_NAME_LENGTH);
				if(StrEqual(ppanPlayerName,ppanMenuName))
				{
					PrintToChatAll("\x04[CUP]\x03 Moved %s to spectators.",ppanPlayerName);
					ForceSpectate(lnClient);
				}
			}
		}
		
		DisplayMenu(ghCupMenu, anClient, 0);
	}
	else if(ahAction == MenuAction_Cancel)
	{
		geAdminInMenu = false;
	}
	else if (ahAction == MenuAction_End)
	{
		//Do nothing
	}
	
	return 0;
}

DisplayWinnerSelectionMenu(anWinnerIndex,anClient)
{
	new Handle:lhMenu = INVALID_HANDLE;
	
	if(anWinnerIndex == 0)
	{
		lhMenu = CreateMenu(cbFirstPlaceMenuHandler,MENU_ACTIONS_ALL);
		SetMenuTitle(lhMenu, "Set first place");
	}
	else if(anWinnerIndex == 1)
	{
		lhMenu = CreateMenu(cbSecondPlaceMenuHandler,MENU_ACTIONS_ALL);
		SetMenuTitle(lhMenu, "Set second place");
	}
	else
	{
		lhMenu = CreateMenu(cbThirdPlaceMenuHandler,MENU_ACTIONS_ALL);
		SetMenuTitle(lhMenu, "Set third place");
	}
	
	AddPlayersToMenu(lhMenu);
	DisplayMenu(lhMenu,anClient,0);
}

public cbFirstPlaceMenuHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	SetWinner(0,ahMenu,ahAction,anClient,anSelection);
	return 0;
}

public cbSecondPlaceMenuHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	SetWinner(1,ahMenu,ahAction,anClient,anSelection);
	return 0;
}

public cbThirdPlaceMenuHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	SetWinner(2,ahMenu,ahAction,anClient,anSelection);
	return 0;
}

SetWinner(anWinnerIndex,Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	if(ahAction != MenuAction_End)
	{
		geAdminInMenu = true;
	}
	
	if(ahAction == MenuAction_Select)
	{
		GetMenuItem(ahMenu, anSelection, gpanWinners[anWinnerIndex], MAX_NAME_LENGTH);
		DisplayMenu(ghCupMenu, anClient, 0);
	}
	else if(ahAction == MenuAction_Cancel)
	{
		geAdminInMenu = false;
	}
	else if (ahAction == MenuAction_End)
	{
		//Do nothing
	}
}

TeleportAdminToNextClient()
{
	static pnCurrClientIndex = 0;
	new lnClient = 0;
	
	for(lnClient=1;lnClient<MaxClients;lnClient++)
	{
		pnCurrClientIndex = (pnCurrClientIndex % MaxClients) + 1;
		
		if(pnCurrClientIndex == 0)
		{
			pnCurrClientIndex = 1;
		}
	
		if(IsPlayerValid(pnCurrClientIndex) == true && gnCupAdminClientIndex != pnCurrClientIndex)
		{
			new Float:larClientPos[3];
			GetEntPropVector(pnCurrClientIndex, Prop_Send, "m_vecOrigin", larClientPos);
			TeleportEntity(gnCupAdminClientIndex, larClientPos, NULL_VECTOR, NULL_VECTOR);
			break;
		}
	}
}

public cbTimeSubMenuHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelection)
{
	new String:lpanInfo[32];
	new lnCupDurationSec = 60;
	geAdminInMenu = true;
	
	if (ahAction == MenuAction_Select)
	{
		//Use GetMenuItem so there is no question about menu item order
		GetMenuItem(ahMenu, anSelection, lpanInfo, sizeof(lpanInfo));
		
		if(strcmp(lpanInfo,MENU_10MIN) == 0)
		{
			lnCupDurationSec = 10 * 60;
		}
		else if(strcmp(lpanInfo,MENU_5MIN) == 0)
		{
			lnCupDurationSec = 5 * 60;
		}
		else if(strcmp(lpanInfo,MENU_3MIN) == 0)
		{
			lnCupDurationSec = 3 * 60;
		}
		else if(strcmp(lpanInfo,MENU_2MIN) == 0)
		{
			lnCupDurationSec = 2 * 60;
		}
		else if(strcmp(lpanInfo,MENU_1MIN) == 0)
		{
			lnCupDurationSec = 1 * 60;
		}
		
		SetConVarInt(ghCupDurationCvar,lnCupDurationSec);
		DisplayMenu(ghCupMenu, anClient, 0);
	}
	else if (ahAction == MenuAction_End)
	{
		
	}
	
	return 0;
}

ToggleNoclip(anClient)
{
	new MoveType:lnMoveType = GetEntityMoveType(anClient);
	
	if(lnMoveType == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(anClient,MOVETYPE_WALK);
	}
	else
	{
		SetEntityMoveType(anClient,MOVETYPE_NOCLIP);
	}
}

SetCupStartPos(anClient)
{
	PrintToChat(gnCupAdminClientIndex,"\x04[CUP]\x03 Start position set");
	GetEntPropVector(anClient, Prop_Send, "m_vecOrigin", garStartPos);
	GetClientEyeAngles(anClient,garStartAngles);
	geStartPosSet = true;
}

CloseCountdownTimer()
{
	if(ghCountdownTimer != INVALID_HANDLE)
	{
		if(CloseHandle(ghCountdownTimer) == true)
		{
			ghCountdownTimer = INVALID_HANDLE;
		}
	}
}

StartCup()
{
	CloseCountdownTimer();
	
	ghCountdownTimer = CreateTimer(1.0,cbCupTimer,INVALID_HANDLE,TIMER_REPEAT);
	
	AllowCheckpoints(false);
	TeleportPlayersToStartPos();
	FreezePlayers();
	geCupInProgress = true;
	
	for(new lnIndex=0;lnIndex<MAX_WINNERS;lnIndex++)
	{
		strcopy(gpanWinners[lnIndex],MAX_NAME_LENGTH-1,"");
	}
}

AllowCheckpoints(bool:aeBool)
{
	new Handle:lhConvar;
	
	lhConvar = FindConVar("sv_allowchecks");
	
	if(lhConvar != INVALID_HANDLE)
	{
		if(aeBool == true)
		{
			SetConVarInt(lhConvar,1);
		}
		else
		{
			SetConVarInt(lhConvar,0);
		}
	}
	else
	{
		LogDebug("Could not find sv_allowchecks convar");
	}
}

bool:IsPlayerValid(anClient)
{
	new bool:leValid = false;

	if(IsClientConnected(anClient) && IsClientAuthorized(anClient)  &&
	   IsClientInGame(anClient) && GetClientTeam(anClient) == TEAM_PLAYERS &&
	   IsPlayerAlive(anClient))
	{
		leValid = true;
	}
	
	return leValid;
}

TeleportPlayersToStartPos()
{
	new lnClient;
	static Float:parZeroVel[3] = { 0.0, 0.0, 0.0 };

	//Set player position and freeze them
	for(lnClient=1;lnClient<MaxClients;lnClient++)
	{
		if(IsPlayerValid(lnClient) == true && gnCupAdminClientIndex != lnClient)
		{
			TeleportEntity(lnClient, garStartPos, garStartAngles, parZeroVel);
		}
	}
}

CancelCup()
{
	if(gnTimeSec < gnCupDurationSec)
	{
		PrintToChatAll("\x04[CUP]\x03 Cup cancelled");
	}

	CloseCountdownTimer();
	AllowCheckpoints(true);
	geCupInProgress = false;
	gnCountDownSec = CUP_START_COUNTDOWN_SEC;
	gnTimeSec = 0;
	UnfreezePlayers();
}

FreezePlayers()
{
	for(new lnClient=1;lnClient<MaxClients;lnClient++)
	{
		if(IsPlayerValid(lnClient) == true && gnCupAdminClientIndex != lnClient)
		{
			SetEntityMoveType(lnClient,MOVETYPE_NONE);
		}
	}
}

UnfreezePlayers()
{
	for(new lnClient=1;lnClient<MaxClients;lnClient++)
	{
		if(IsPlayerValid(lnClient) == true && gnCupAdminClientIndex != lnClient)
		{
			SetEntityMoveType(lnClient,MOVETYPE_WALK);
		}
	}
}

public Action:cbCupTimer(Handle:ahTimer, any:anClient)
{
	gnCountDownSec--;
	gnTimeSec++;
	
	//Count down at start of cup
	if(gnCountDownSec >= 0)
	{
		PlaySoundFromTrie(gaanTimeSounds[gnCountDownSec]);
		
		if(gnCountDownSec == 0)
		{
			UnfreezePlayers();
		}
	}
	else
	{
		//Play sounds for amount of time remaining
		PlayRemainingTimeSounds(gnTimeSec,gnCupDurationSec);
		
		SendCupTimePanel(gnCupDurationSec - gnTimeSec);
	}
		
	//If the cup has ended
	if(gnTimeSec >= gnCupDurationSec)
	{
		FreezePlayers();
		ghCountdownTimer = INVALID_HANDLE;
		PrintToChatAll("\x04[CUP]\x03 Cup time expired");
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

SendCupTimePanel(anTimeRemainingSec)
{
	decl String:apanHudHintText[16];
	new lnMinutes = anTimeRemainingSec / 60;
	new lnSeconds = anTimeRemainingSec % 60;
	
	if(lnSeconds < 10)
	{
		Format(apanHudHintText,sizeof(apanHudHintText),"   %i:0%i",lnMinutes,lnSeconds);
	}
	else
	{
		Format(apanHudHintText,sizeof(apanHudHintText),"   %i:%i",lnMinutes,lnSeconds);
	}
	
	new Handle:lhPanel = CreatePanel();
	SetPanelTitle(lhPanel, "Cup time");
	SetPanelKeys(lhPanel,0xFFFFFFFF);
	DrawPanelText(lhPanel,apanHudHintText);
	SetPanelKeys(lhPanel, (1<<8)|(1<<9));
	
	for(new lnClient=1;lnClient<MaxClients;lnClient++)
	{
		//Show for valid clients except the cup admin when in menu
		if(IsClientInGame(lnClient) == true &&
		   (geAdminInMenu != true || lnClient != gnCupAdminClientIndex))
		{
			SendPanelToClient(lhPanel, lnClient, cbTimeLeftPanelHandler, 1);
			
			//Make the player slot9 so that any other slot commands are not eaten by the panel, which
			//would prevent weapon switching.  The panel will flash a bit due to this.
			ClientCommand(lnClient,"slot9");
		}
	}
	
	CloseHandle(lhPanel);
}

public cbTimeLeftPanelHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelect)
{
	if (ahAction == MenuAction_Select)
	{
	}
	else if (ahAction == MenuAction_Cancel)
	{
	}
}

PlayRemainingTimeSounds(anTimeSec,anCupDurationSec)
{
	static bool:peSaySeconds = false;
	static bool:peSayMinutes = false;
	static bool:peSayRemaining = false;
	new lnTimeRemaining = anCupDurationSec - anTimeSec;
	
	//Don't list times above 10 minutes
	if(lnTimeRemaining > (60 * 10) || anTimeSec == 0)
	{
		peSaySeconds = false;
		peSayMinutes = false;
		peSayRemaining = false;
		return;
	}
	
	if(peSayMinutes)
	{
		PlaySoundFromTrie("soul/cuptimer/minutes.wav");
		peSayMinutes = false;
		peSayRemaining = true;
	}
	else if(peSaySeconds)
	{
		PlaySoundFromTrie("soul/cuptimer/seconds.wav");
		peSaySeconds = false;
		peSayRemaining = true;
	}
	else if(peSayRemaining)
	{
		PlaySoundFromTrie("soul/cuptimer/remaining.wav");
		peSayRemaining = false;
	}
	//Count down the last 10 seconds
	else if(lnTimeRemaining >= 0 && lnTimeRemaining <= 10)
	{
		PlaySoundFromTrie(gaanTimeSounds[lnTimeRemaining]);
	}
	//Announce the minute marks
	else if((lnTimeRemaining % 60) == 0)
	{
		PlaySoundFromTrie(gaanTimeSounds[lnTimeRemaining/60]);
		peSayMinutes = true;
	}
	//Announce the 30 second mark
	else if(lnTimeRemaining == 30)
	{
		PlaySoundFromTrie("soul/cuptimer/thirty.wav");
		peSaySeconds = true;
	}
}

//All this sound stuff is a workaround for precaching not working correctly in SM.
//See: https://forums.alliedmods.net/archive/index.php/t-87406.html
SetUpSoundPrecacheTrie()
{
	if(ghSoundPrecacheTrie == INVALID_HANDLE)
	{
		ghSoundPrecacheTrie = CreateTrie();
	}
	else
	{
		ClearTrie(ghSoundPrecacheTrie);
	}
}

PrepareSoundInTrie(const String:apanSound[])
{
	new bool:aeValue;
	if(GetTrieValue(ghSoundPrecacheTrie,apanSound,aeValue) == false)
	{
		PrecacheSound(apanSound);
		SetTrieValue(ghSoundPrecacheTrie,apanSound,true);
	}
}

PlaySoundFromTrie(const String:apanSound[])
{
	PrepareSoundInTrie(apanSound);
	EmitSoundToAll(apanSound);
}

