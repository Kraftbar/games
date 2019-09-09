-- Author       : Caat
-- Addon	    : Caats Emote Button Leiste Classic
-- Create Date  : 16.08.2009
-- Last Updated : 27.08.2019


function Button1_OnClick()
	DoEmote("Hello")
end

function Button2_OnClick()
	DoEmote("Wave")
end

function Button3_OnClick()
	DoEmote("Bye")
end

function Button4_OnClick()
	DoEmote("Thank")
end

function Button5_OnClick()
	DoEmote("Apologize")
end

function Button6_OnClick()
	DoEmote("Nod")
end

function Button7_OnClick()
	DoEmote("No")
end

function Button8_OnClick()
	DoEmote("Brb")
end



function Button20_OnClick()
	DoEmote("Kiss")
end

function Button21_OnClick()
	DoEmote("Hug")
end

function Button22_OnClick()
	DoEmote("Cuddle")
end

function Button23_OnClick()
	DoEmote("Shy")
end

function Button24_OnClick()
	DoEmote("Blink")
end

function Button25_OnClick()
	DoEmote("Cry")
end

function Button26_OnClick()
	DoEmote("Lick")
end

function Button27_OnClick()
	DoEmote("Bite")
end

function Button28_OnClick()
	DoEmote("Comfort")
end

function Button29_OnClick()
	DoEmote("Whistle")
end

function Button30_OnClick()
	DoEmote("Soothe")
end

function Button33_OnClick()
	DoEmote("Sigh")
end

function Button34_OnClick()
	DoEmote("Pet")
end

function Button35_OnClick()
	DoEmote("Snarl")
end

function Button36_OnClick()
	DoEmote("love")
end




function Button40_OnClick()
	DoEmote("Applaud")	
end

function Button41_OnClick()
	DoEmote("Bow")		
end

function Button42_OnClick()
	DoEmote("Cheer")	
end

function Button43_OnClick()
	DoEmote("Congratulate")	
end

function Button44_OnClick()
	DoEmote("Bored")	
end

function Button45_OnClick()
	DoEmote("Snicker")	
end

function Button46_OnClick()
	DoEmote("Dance")	
end

function Button47_OnClick()
	DoEmote("Fidget")	
end

function Button48_OnClick()
	DoEmote("Yawn")	
end





function Button60_OnClick()
	DoEmote("Mock")	
end

function Button62_OnClick()
	DoEmote("Fart")	
end

function Button63_OnClick()
	DoEmote("Mourn")	
end

function Button64_OnClick()
	DoEmote("Guffaw")	
end

function Button65_OnClick()
	DoEmote("Shoo")	
end

function Button66_OnClick()
	DoEmote("Fail")	
end

function Button67_OnClick()
	DoEmote("Spit")	
end

function Button68_OnClick()
	DoEmote("Pray")	
end

function Button69_OnClick()
	DoEmote("Golfclap")	
end


local an1=0;

function Leiste1_OnClick()
if (an1==0) then 
	Gruppe1:Hide();
	an1=1;
else
	Gruppe1:Show();
	an1=0;
end
end

