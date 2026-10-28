--[[
    EqStaffNames.lua
    First names for staff candidates: 40 women's and 40 men's names from many countries, so a
    yard's staff list reads like a real mixed team. A candidate gets one of these and a last
    initial ("Amara K."). Names only, no portraits.
]]

EqStaffNames = {}

EqStaffNames.WOMEN = {
    "Amara", "Aiko", "Ana", "Anja", "Astrid", "Bianca", "Camille", "Chiara", "Daniela", "Elena",
    "Emily", "Fatima", "Freya", "Hana", "Ingrid", "Isabel", "Jade", "Kaia", "Leila", "Lucia",
    "Maeve", "Maja", "Mariana", "Mei", "Nadia", "Nia", "Olivia", "Priya", "Rosa", "Sakura",
    "Sofia", "Siobhan", "Tamar", "Valentina", "Wiktoria", "Yasmin", "Zara", "Ayesha", "Eva", "Ngozi",
}

EqStaffNames.MEN = {
    "Ahmed", "Alejandro", "Andre", "Arjun", "Bjorn", "Carlos", "Connor", "Dmitri", "Emil", "Felipe",
    "Finn", "Hamid", "Hiroshi", "Ivan", "Jakob", "Jamal", "Jonas", "Kenji", "Kwame", "Liam",
    "Luca", "Mateo", "Mehmet", "Niko", "Olu", "Pavel", "Pedro", "Rafael", "Ravi", "Sami",
    "Santiago", "Sean", "Tariq", "Tomas", "Wei", "Yusuf", "Lars", "Marco", "Diego", "Henrik",
}

-- Last initials, without the rarer letters.
EqStaffNames.INITIALS = "ABCDEFGHJKLMNOPRSTVWY"


--- A name for a new candidate.
--- @param rng table EqRandom
--- @return string name such as "Amara K."
--- @return string gender "female" or "male", for the portrait
function EqStaffNames.roll(rng)
    local female = rng:next() < 0.5
    local list = female and EqStaffNames.WOMEN or EqStaffNames.MEN
    local first = list[math.min(#list, math.floor(rng:next() * #list) + 1)]
    local at = math.min(#EqStaffNames.INITIALS, math.floor(rng:next() * #EqStaffNames.INITIALS) + 1)
    return string.format("%s %s.", first, string.sub(EqStaffNames.INITIALS, at, at)), female and "female" or "male"
end


--- @param name string such as "Amara K."
--- @return string|nil gender "female" or "male", nil for a name not on the lists
function EqStaffNames.genderOf(name)
    local first = string.match(name or "", "^(%S+)")
    for _, known in ipairs(EqStaffNames.WOMEN) do
        if known == first then return "female" end
    end
    for _, known in ipairs(EqStaffNames.MEN) do
        if known == first then return "male" end
    end
    return nil
end
