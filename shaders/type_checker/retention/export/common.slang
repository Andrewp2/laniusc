// Lane numbering of the export steps' 2D dispatches.
public uint export_lane(uint3 dtid) { return dtid.x + dtid.y * 16776960u; }
