<%@ WebHandler Language="C#" Class="Handler" %>

using System.Web;
using System.Text;
using System.IO;
using Dynamicweb.Rendering.Designer;
using System.Text.RegularExpressions;

public class Handler : IHttpHandler {
	private HttpContext context;

	public void ProcessRequest(HttpContext context) {
		this.context = context;

		this.context.Response.ContentType = "text/html";

		var templates = GetTemplateFiles();

		Write(@"
<!DOCTYPE html>

<html xmlns='http://www.w3.org/1999/xhtml'>
	<head>
		<meta charset='utf-8'/>
		<title>Check Templates</title>
<style>
strong {
	color: red;
}
</style>
	</head>
<body>
<div id='content'>");

		Write("<h1>#templates: {0}</h1>", templates.Count);

		foreach (var template in templates) {
			CheckTemplate(template);
		}

		Write(@"</div>
</body>
</html>");
	}

	private bool verbose = true;

	private void CheckTemplate(TemplateFile template) {
		using (var reader = new System.IO.StreamReader(template.TemplateFileInfo.FullName)) {
			string line;
			var ifLevel = 0;
			var lineNumber = 0;
			var errorLineNumber = -1;
			var content = new StringBuilder();
			while ((line = reader.ReadLine()) != null) {
				lineNumber++;
				line = Regex.Replace(line, "<!--@(?<keyword>If|Else|EndIf)", m => {
						var keyword = m.Groups["keyword"].Value;
						if (keyword == "If") {
							ifLevel += 1;
						}
						var result = string.Format("{0}[{1}]", m.Value, ifLevel);
						if (keyword == "EndIf") {
							ifLevel -= 1;
						}
						return m.Value; //result;
					});
				if (ifLevel < 0 && errorLineNumber < 0) {
					errorLineNumber = lineNumber;
					content.AppendFormat("{0,4}:\t[[strong]]{1}[[/strong]]", lineNumber, line);
				} else {
					content.AppendFormat("{0,4}:\t{1}", lineNumber, line);
				}
				content.AppendLine();
			}
			if (ifLevel != 0) {
				var templateUrl = template.TemplateName;
				Write("<fieldset>");
				Write("<legend>{0}</legend>", templateUrl);
				Write("<div class='error'>{0} at {1}</div>", "Missing @"+(ifLevel > 0 ? "EndIf" : "If"), (errorLineNumber > 0) ? "line "+errorLineNumber : "end of file");

				var editor = "FileManager_FileEditorV2.aspx";
				// editor = "Simple.aspx";
				var editUrl = string.Format("{0}://{1}/Admin/Filemanager/FileEditor/{2}?Folder={3}&amp;File={4}",
																		context.Request.Url.Scheme, context.Request.Url.Host, editor,
																		UrlEncode(template.Location), UrlEncode(template.Name));
				Write("<div class='edit'><a target='edittemplate' href='{0}'>Edit template ({1})</a></div>", editUrl, templateUrl);

				if (verbose) {
					Write("<hr/>");
					Write("<pre>{0}</pre>", Regex.Replace(HtmlEncode(content), @"\[{2,}(/?)([^\]]+)\]{2,}", "<$1$2>"));
				}
				Write("</fieldset>");
			}
			reader.Close();
		}
	}

	private string HtmlEncode(object o) {
		return Server.HtmlEncode(o.ToString());
	}

	private string UrlEncode(object o) {
		return Server.UrlEncode(o.ToString());
	}

	private HttpServerUtility Server {
		get {
			return System.Web.HttpContext.Current.Server;
		}
	}

	private void Write(string s) {
		this.context.Response.Write(s);
	}

	private void WriteLine(string s) {
		this.context.Response.Write(s);
		Write("\n");
	}

	private void Write(string format, params object[] args) {
		this.context.Response.Write(string.Format(format, args));
	}

	private void WriteLine(string format, params object[] args) {
		Write(format, args);
		Write("\n");
	}

	private void Write(object o) {
		this.context.Response.Write(o.ToString());
	}

	private void WriteLine(object o) {
		Write(o);
		Write("\n");
	}

	private TemplateFileCollection GetTemplateFiles() {
		var directory = new DirectoryInfo(Server.MapPath("~/Files/Templates/"));
		var collection = new TemplateFileCollection();
		GetTemplateFiles(directory, collection);
		return collection;
	}

	private void GetTemplateFiles(DirectoryInfo directory, TemplateFileCollection collection) {
		foreach (var file in TemplateFile.GetTemplateFiles(directory.FullName)) {
			collection.Add(file);
		}
		foreach (var dir in directory.GetDirectories()) {
			GetTemplateFiles(dir, collection);
		}
	}

	public bool IsReusable {
		get {
			return false;
		}
	}
}
