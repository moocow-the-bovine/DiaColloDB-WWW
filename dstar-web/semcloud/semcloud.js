//-*- Mode: Javascript; coding: utf-8; -*-

//-- user query params
var user_query = {};

//=============================================================================)
// to=terms

var jqCloudOptions = {
    delayedMode: true, //default: true if n>50
    shape: false, // default: elliptic shape
    encodeURI: false, //default=true
    removeOverflowing: true //default=true
};

//----------------------------------------------------------------------
// terms = [{text: "Ipsum", weight: 10.5, html: {title: "My Title", "class": "custom-class"}, link: {href: "http://jquery.com/", target: "_blank"}}, ...]
function cloudInit() {
    semQuery({param: user_query, success: cloudSuccess});
}


//----------------------------------------------------------------------
var maptoAlias = {
    "pages":"docs",
    "books":"cats",
    "volumes":"cats",
    "vols":"cats",
};
function cloudSuccess(data,textStatus,jqXHR) {
    terms = [];
    var mapto = user_query.to;
    if (maptoAlias[mapto] != null) { mapto=maptoAlias[mapto]; }
    data.forEach(function(e) {
	var t  = { text:e.label, weight:e.sim,  link:"(none)" }
        var tp = cloneObject(user_query);
	if (mapto == "terms") {
	    tp.q   = e.label;
	    t.link = "terms.perl?" + jQuery.param(tp);
	}
	else if (mapto == "docs") {
	    tp.q   = "page=" + e.label;
	    t.link = "pages.perl?" + jQuery.param(tp);
	}
	else if (mapto == "cats") {
	    tp.q   = "book=" + e.label;
	    t.link = "books.perl?" + jQuery.param(tp);
	}
	else {
	    console.log("unknown map-target mode to=" + user_query.to);
	}
	terms.push(t);
    });

    $("#termCloud").jQCloud(terms,jqCloudOptions);
}


//=============================================================================)
// generic semq guts

//----------------------------------------------------------------------
var semq_url_base  = window.location.href.replace(/[^\/]*$/,'semq.perl');
var semq_url_local = "./semq.perl";
var semq_params_default = {
    "q" : null,
    "to" : "terms",
    "k" : 10,
    "b" : null,
    "beta": null
};

//----------------------------------------------------------------------
function semQuery(opts) {
    //-- default options
    if (opts.url==null)     { opts.url     = semq_url_local; }
    if (opts.param==null)   { opts.param   = user_query; }
    if (opts.success==null) { opts.success = semqOnSuccess; }
    if (opts.failure==null) { opts.failure = semqOnFailure; }

    //-- set default query parameters
    param = cloneObject(opts.param,true);
    keys(semq_params_default).forEach(function(k) {
	if (opts[k] != null)  { param[k] = opts[k]; }
	if (param[k] == null) { param[k] = semq_params_default[k]; }
	if (param[k] == null) { delete param[k]; }
    });

    //-- send request
    $.ajax({
	type: "GET",
	url: opts.url+'?'+jQuery.param(param),
	dataType: "json",
	success: opts.success,
	failure: opts.failure,
    });
}

//----------------------------------------------------------------------
function semqOnSuccess(data,textStatus,jqXHR) {
    alert("k-best request succeeded: "+textStatus);
}

//----------------------------------------------------------------------
function semqOnFailure(errMsg) {
    alert("k-best request failed: "+errMsg);
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


