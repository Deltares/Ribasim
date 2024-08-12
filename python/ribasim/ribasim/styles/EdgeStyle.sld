<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" version="1.1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:se="http://www.opengis.net/se" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.1.0/StyledLayerDescriptor.xsd" xmlns:ogc="http://www.opengis.net/ogc" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <NamedLayer>
  <se:Name>Edge</se:Name>
  <UserStyle>
   <se:Name>Edge</se:Name>
   <se:FeatureTypeStyle>
    <se:Rule>
     <se:Name>flow</se:Name>
     <se:Description>
      <se:Title>flow</se:Title>
     </se:Description>
     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">
      <ogc:PropertyIsEqualTo>
       <ogc:PropertyName>edge_type</ogc:PropertyName>
       <ogc:Literal>flow</ogc:Literal>
      </ogc:PropertyIsEqualTo>
     </ogc:Filter>
     <se:LineSymbolizer>
      <se:Stroke>
       <se:SvgParameter name="stroke">#3690c0</se:SvgParameter>
       <se:SvgParameter name="stroke-width">2</se:SvgParameter>
       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>
       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>
      </se:Stroke>
     </se:LineSymbolizer>
     <se:LineSymbolizer>
      <se:VendorOption name="placement">centralPoint</se:VendorOption>
      <se:Stroke>
       <se:GraphicStroke>
        <se:Graphic>
         <se:Mark>
          <se:WellKnownName>filled_arrowhead</se:WellKnownName>
          <se:Fill>
           <se:SvgParameter name="fill">#3690c0</se:SvgParameter>
          </se:Fill>
          <se:Stroke/>
         </se:Mark>
         <se:Size>11</se:Size>
        </se:Graphic>
       </se:GraphicStroke>
      </se:Stroke>
     </se:LineSymbolizer>
    </se:Rule>
    <se:Rule>
     <se:Name>control</se:Name>
     <se:Description>
      <se:Title>control</se:Title>
     </se:Description>
     <ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">
      <ogc:PropertyIsEqualTo>
       <ogc:PropertyName>edge_type</ogc:PropertyName>
       <ogc:Literal>control</ogc:Literal>
      </ogc:PropertyIsEqualTo>
     </ogc:Filter>
     <se:LineSymbolizer>
      <se:Stroke>
       <se:SvgParameter name="stroke">#808080</se:SvgParameter>
       <se:SvgParameter name="stroke-width">2</se:SvgParameter>
       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>
       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>
      </se:Stroke>
     </se:LineSymbolizer>
     <se:LineSymbolizer>
      <se:VendorOption name="placement">centralPoint</se:VendorOption>
      <se:Stroke>
       <se:GraphicStroke>
        <se:Graphic>
         <se:Mark>
          <se:WellKnownName>filled_arrowhead</se:WellKnownName>
          <se:Fill>
           <se:SvgParameter name="fill">#808080</se:SvgParameter>
          </se:Fill>
          <se:Stroke/>
         </se:Mark>
         <se:Size>11</se:Size>
        </se:Graphic>
       </se:GraphicStroke>
      </se:Stroke>
     </se:LineSymbolizer>
    </se:Rule>
    <se:Rule>
     <se:Name></se:Name>
     <se:Description>
      <se:Title>"edge_type" is ''</se:Title>
     </se:Description>
     <se:ElseFilter xmlns:se="http://www.opengis.net/se"/>
     <se:LineSymbolizer>
      <se:Stroke>
       <se:SvgParameter name="stroke">#000000</se:SvgParameter>
       <se:SvgParameter name="stroke-width">2</se:SvgParameter>
       <se:SvgParameter name="stroke-linejoin">bevel</se:SvgParameter>
       <se:SvgParameter name="stroke-linecap">square</se:SvgParameter>
      </se:Stroke>
     </se:LineSymbolizer>
     <se:LineSymbolizer>
      <se:VendorOption name="placement">centralPoint</se:VendorOption>
      <se:Stroke>
       <se:GraphicStroke>
        <se:Graphic>
         <se:Mark>
          <se:WellKnownName>filled_arrowhead</se:WellKnownName>
          <se:Fill>
           <se:SvgParameter name="fill">#000000</se:SvgParameter>
          </se:Fill>
          <se:Stroke/>
         </se:Mark>
         <se:Size>11</se:Size>
        </se:Graphic>
       </se:GraphicStroke>
      </se:Stroke>
     </se:LineSymbolizer>
    </se:Rule>
    <se:Rule>
     <se:TextSymbolizer>
      <se:Label>
       <!--SE Export for concat(name, ' #', fid) not implemented yet-->Placeholder</se:Label>
      <se:Font>
       <se:SvgParameter name="font-family">Open Sans</se:SvgParameter>
       <se:SvgParameter name="font-size">13</se:SvgParameter>
      </se:Font>
      <se:LabelPlacement>
       <se:LinePlacement>
        <se:PerpendicularOffset>4</se:PerpendicularOffset>
        <se:GeneralizeLine>true</se:GeneralizeLine>
       </se:LinePlacement>
      </se:LabelPlacement>
      <se:Fill>
       <se:SvgParameter name="fill">#323232</se:SvgParameter>
      </se:Fill>
     </se:TextSymbolizer>
    </se:Rule>
   </se:FeatureTypeStyle>
  </UserStyle>
 </NamedLayer>
</StyledLayerDescriptor>
