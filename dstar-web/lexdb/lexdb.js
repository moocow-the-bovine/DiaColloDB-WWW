//-*- Mode: Javascript; coding: utf-8 -*-

//==============================================================================
// Globals
var hrows = null;
var trows = null;

var dstar_url = "../dstar.perl";

var lexdb_cab_enabled = false;
var cab_url    = "cab/query";
var cab_params = {"a":"default.base","fmt":"json","clean":0,"raw":0};
var caberr_base = "/caberr/";


//==============================================================================

//----------------------------------------------------------------------
var wFields = ["u","w","v"];
var ddcFields = ["u","w","v","p","l"];
function viewInit() {
    //-- setup callbacks
    if (lexdb_cab_enabled) {
	$("tr.viewtr").click( detailClick );
    }
    $("tr.viewtr").hover( viewTrHover );

    //-- init cab data & trows
    trows = [];
    var stokens = [];
    for (rowid in hrows) {
	var row = hrows[rowid];
	trows[rowid] = $("tr.viewtr[rowid="+rowid+"]");
	wFields.forEach(function(wf) {
	    if (row[wf] != null) { stokens.push({"text":row[wf], "rowid":rowid, "rowkey":wf, "id":wf+"."+String(rowid)}); }
	});
    }

    if (lexdb_cab_enabled) {
	cabRequestJson({"body":[{"tokens":stokens}]},
		       { success: viewInitCabSuccess });
    }

    //-- setup ddc kwic links
    for (rowid in hrows) {
	var row = hrows[rowid];
	var tr  = trows[rowid];
	var qconds = [];
	ddcFields.forEach(function(qf) {
	    if (row[qf] != null) { qconds.push("$"+qf+"=@"+escapeDDC(row[qf])); }
	});
	tr.find(".kwicButton").prop('href',
				    dstar_url +'?' + jQuery.param({"fmt":"kwic",
								   "q": "("+qconds.join(" with ")+") #sep"//+" #random"
								  }));
    }

    //-- setup pos-status flags
    for (rowid in hrows) {
	var p   = hrows[rowid].p;
	var cls = 'mokGood';
	if (p != null && p.search(/^(FM|NE|XY)/) != -1) { cls='mokUgly'; }
	trows[rowid].find("td.viewtd.view_p").addClass(cls);
    }

}


//----------------------------------------------------------------------
function viewInitCabSuccess(data,textStatus,jqXHR) {
    data.body[0].tokens.forEach(function(w) {
	hrows[w.rowid]["cab_"+w.rowkey] = w;

	var st  = cabTrafficStatus(w);
	var cls = "mok" + st.charAt(0).toUpperCase() + st.substr(1);
	trows[w.rowid].find("td.viewtd.view_"+w.rowkey).addClass(cls);
    });

    //alert("viewInitCabSuccess();");
}

//----------------------------------------------------------------------
function viewTrHover(ev) {
    var isEnter = (ev.type == "mouseenter");
    var etarget  = $(ev.currentTarget);
    var tr       = etarget.add(etarget.parents("tr.viewtr")).filter(".viewtr");
    if (isEnter) {
	tr.addClass("hovering");
    } else {
	tr.removeClass("hovering");
    }
}

//----------------------------------------------------------------------
var detailFields = ["u","w","v","p","l","f"];
function detailClick(ev) {
    var target = $(ev.currentTarget);
    var rowid  = target.add(target.parents("tr[rowid]")).attr("rowid");
    var row    = hrows[rowid];
    if (row == null) {
	throw "No row defined for rowid="+rowid;
    }

    $(".detailsHowto").add(".detailsContent").hide();

    //-- get cab doc for row
    $(".cabData").text("loading...")
    var rtokens = [];
    wFields.forEach(function(wf) {
	if (row[wf] != null) { rtokens.push({"text":row[wf], "id":wf+"."+String(rowid)}); }
    });
    cabRequestText({"body":[{"tokens":rtokens}]},
		   { success: cabDetailSuccess });
    

    $(".detailsContent").fadeIn();
}

//----------------------------------------------------------------------
function cabDetailSuccess(data,textStatus,jqXHR) {
    data = (data
	    .replace(/&/g,"&amp;")
	    .replace(/"/g,"&quot;")
	    .replace(/'/g,"&apos;")
	    .replace(/>/g,"&gt;")
	    .replace(/</g,"&lt;")
	    .replace(/\n+$/g, "\n")
	    //.replace(/[ ]/g,"&nbsp;")
	    .replace(/^([^\t\r\n%]+)/gm, "<a class='cabText'>$1</a>")
	    .replace(/^(%%[^\r\n]*)/gm, "<span class='cabComment'>$1</span>")
	    .replace(/^\t\+\[([^\]]+)\](?: |&nbsp;)(.*)$/gm, "<span class='cabAttr $1'><span class='cabAttrName'>+[$1]</span><span class='cabAttrValue'>$2</span></span>")
	   );
    $(".cabData").html(data);

    //-- hide some stuff
    ["id","xlit"].forEach(function(a) { $(".cabAttr."+a).hide(); });

    //-- hack: setup caberr links
    $(".cabAttr.errid .cabAttrValue").each(function() {
	var txt = $(this).text();
	if (txt.search(/^[0-9]+$/) != -1) {
	    $(this).html("<a href='"+caberr_base+"edit.perl?id="+txt+"'>"+txt+"</a><br/>");
	}
    });

    //-- hack: setup text links
    $(".cabText").each(function() {
	var txt=$(this).text();
	var wf =$(this).nextUntil(".cabText").filter(".cabAttr.id").find(".cabAttrValue").first().text().replace(/\..*$/,'');
	$(this).prop('href',
		     dstar_url +'?' + jQuery.param({"fmt":"kwic",
						    "q": "$"+wf+"=@"+escapeDDC(txt)+" #random"
						   }));
	$(this).append("<span class='cabTextType'>($"+wf+")</span>");
    });
}


//==============================================================================
// CAB Stuff

//--------------------------------------------------------------
function cabRequestJson(cabDoc,opts) {
    opts = cloneObject(opts,true);
    if (opts.url==null)     { opts.url     = cab_url; }
    if (opts.param==null)   { opts.param   = cloneObject(cab_params); }
    if (opts.success==null) { opts.success = cabOnSuccess; }
    if (opts.failure==null) { opts.failure = cabOnFailure; }
    opts.param.fmt = "json";
    $.ajax({
	type: "POST",
	url: opts.url+'?'+jQuery.param(opts.param),
	data: JSON.stringify(cabDoc),
	contentType: "application/json; charset=utf-8",
	dataType: "json",
	success: opts.success,
	failure: opts.failure
    });
}

//--------------------------------------------------------------
function cabRequestText(cabDoc,opts) {
    opts = cloneObject(opts,true);
    if (opts.url==null)     { opts.url     = cab_url; }
    if (opts.param==null)   { opts.param   = cloneObject(cab_params); }
    if (opts.success==null) { opts.success = cabOnSuccess; }
    if (opts.failure==null) { opts.failure = cabOnFailure; }
    opts.param.fmt = "text";
    $.ajax({
	type: "POST",
	url: opts.url+'?'+jQuery.param(opts.param),
	data: cabDocText(cabDoc),
	contentType: "text/plain; charset=utf-8",
	dataType: "text",
	success: opts.success,
	failure: opts.failure
    });
}

//--------------------------------------------------------------
function cabDocText(cabDoc) {
    if (!(cabDoc instanceof Object)) { return cabDoc; }
    var str = "";
    cabDoc.body.forEach(function(s) {
	if (s.id != null) {
	    str += "%% Sentence "+s.id+"\n";
	}
	s.tokens.forEach(function(w) {
	    str += w.text + "\n";
	    for (wf in w) {
		if (wf == "text") { continue; }
		str += "\t["+wf+"] " + w[wf] + "\n";
	    }
	});
	str += "\n";
    });
    return str;
}

//-- status = cabTrafficStatus(tok)
// + status is one of "good", "bad", "ugly", "multi"
function cabTrafficStatus(tok) {
    var xlit_id    = (tok.xlit!=null ? (tok.text == tok.xlit.latin1Text) : (tok.text.match(/^[a-zA-ZäöüÄÖÜß]*$/)));
    var has_morph  = (tok.hasmorph || (tok.morph!=null && tok.morph.length>0));
    var has_mlatin = (tok.mlatin!=null && tok.mlatin.length>0);
    var has_spaces = (tok.text.search(/[\s_]/) != -1);
    var is_msafe   = (tok.msafe == null ? false : Boolean(Number(tok.msafe)));
    if (xlit_id && is_msafe && has_morph)			{ return 'good'; }
    else if (xlit_id && (has_morph || has_mlatin || is_msafe))	{ return 'ugly'; }
    else if (has_spaces)	{ return 'multi'; }
    else 			{ return 'bad'; }
}

//--------------------------------------------------------------
function cabOnSuccess(data,textStatus,jqXHR) {
    alert("CAB request succeeded: "+textStatus);
}

//--------------------------------------------------------------
function cabOnFailure(errMsg) {
    alert("CAB request failed: "+errMsg);
}

//==============================================================================
// Escapes etc

function escapeDDC(s) {
    if (s.match(/^[a-zA-Z0-9äöüÄÖÜſͤ]+$/)) { return s; }
    return "'" + s.replace('\\','\\\\').replace("'","\\'") + "'";
}

function escapeSQL(s) {
    return "'" + s.replace("'","''") + "'";
}

//==============================================================================
// Generic Utils

//--------------------------------------------------------------
// generic: hash keys, values

function keys(obj) {
    if (!(obj instanceof Object)) { return []; }
    var keys = [];
    for (k in obj) { keys.push(k);  }
    return keys;
}
function values(obj) {
    if (!(obj instanceof Object)) { return []; }
    var vals = [];
    for (k in obj) { vals.push(obj[k]); }
    return vals;
}

//--------------------------------------------------------------
// generic: (deep|shallow) object copy

function cloneObject(oldObject,deepClone) {
    if (deepClone==null || Boolean(deepClone)) {
	return jQuery.extend(true, {}, oldObject);
    } else {
	return jQuery.extend({}, oldObject);
    }
}
