function resourceName = gpibAddress(primaryAddress, interfaceID)
arguments
    primaryAddress uint8
    interfaceID uint8 = 0;
end

assert(primaryAddress >= 0 && primaryAddress <= 30);

resourceName = sprintf("GPIB%d::%d::INSTR", interfaceID, primaryAddress);

end