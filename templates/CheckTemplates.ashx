<%@ WebHandler Language="C#" Class="Handler" %>

using System;
using System.Web;
using System.Text;
using System.IO;
using System.Collections.Generic;
using Dynamicweb.Rendering.Designer;
using System.Text.RegularExpressions;

public class Handler : IHttpHandler
{
	private bool verbose = false;

	private string sourceUrl = "https://raw.github.com/mri-dynamicweb/misc/master/templates/CheckTemplates.ashx";

	private void Update()
	{
		try
		{
			Response.ContentType = "text/html";
			Write("Downloading source from {0} ...", sourceUrl); Response.Flush();
			var client = new System.Net.WebClient();
			var remoteScript = client.DownloadString(sourceUrl);
			WriteLine(" done.<br/>"); Response.Flush();

			var path = Request.PhysicalPath;
			var localScript = File.ReadAllText(path);

			if (localScript != remoteScript)
			{
				Write("Writing to file {0} ...", path); Response.Flush();
				File.WriteAllText(path, remoteScript);
				WriteLine(" done.<br/>"); Response.Flush();
			}
			else
			{
				Write("Script up to date.<br/>"); Response.Flush();
			}

			Write("Reloading {0} ...", HttpUtility.JavaScriptStringEncode(Request.Path)); Response.Flush();
			System.Threading.Thread.Sleep(1000);
			Write("<script>document.location.href = '{0}';</script>", HttpUtility.JavaScriptStringEncode(Request.Path));
		}
		catch (Exception ex)
		{
			WriteLine();
			WriteLine();
			Write(ex.Message);
		}
		Response.End();
	}

	public void ProcessRequest(HttpContext context)
	{
		Initialize(context);

		if (Request.HttpMethod == "POST" && Request["action"] == "update")
		{
			Update();
		}

		Response.ContentType = "text/html";

		this.verbose = Request["verbose"] == "true";

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
<body>");

		Write(@"
<form>
<label>Filter (Regex) <input type='text' name='filter' value='{0}'/></label>
<button type='submit'>OK</button>
</form>
", HttpUtility.HtmlEncode(Request["filter"]));

		Write("<div id='content'>");

		Write("<h1>#templates: {0}</h1>", templates.Count);

		var numberOfSuccesses = 0;
		foreach (var template in templates)
		{
			if (!CheckInclude(template)) continue;
			if (!CheckIfCase(template)) continue;
			if (!CheckIf(template)) continue;
			numberOfSuccesses++;
		}

		if (numberOfSuccesses == templates.Count)
		{
			Write("All templates ok");
		}

		Write(@"</div>

<form method='post'>
<button type='submit' name='action' value='update'>Update this script from GitHub</button><a href='{0}'>{0}</a>
</form>

</body>
</html>", HttpUtility.HtmlEncode(sourceUrl));
	}

	private bool CheckInclude(TemplateFile template)
	{
		var errors = new List<string>();

		var path = template.TemplateFileInfo.FullName;
		var content = File.ReadAllText(path);
		var folder = Path.GetDirectoryName(path);
		var includePattern = new Regex("<!--@Include\\((?<filename>.*?)\\)-->");
		foreach (Match match in includePattern.Matches(content))
		{
			var includeFilename = match.Groups["filename"].Value;
			var includeFile = new FileInfo(Path.Combine(folder, includeFilename));
			if (!includeFile.Exists)
			{
				var message = string.Format("Include file \"{0}\" (\"{1}\") not found", includeFilename, GetTemplateLocation(includeFile.FullName));
				errors.Add(message);
			}
		}
		return ReportErrors(errors, template, content);
	}

	private bool CheckIfCase(TemplateFile template)
	{
		using (var reader = new System.IO.StreamReader(template.TemplateFileInfo.FullName))
		{
			string line;
			var ifLevel = 0;
			var lineNumber = 0;
			var errors = new List<string>();
			var content = new StringBuilder();
			while ((line = reader.ReadLine()) != null)
			{
				lineNumber++;
				var matches = Regex.Matches(line, "<!--(?<stuff>@(?:(?:If( Not)?( Defined)?)|Else))", RegexOptions.IgnoreCase);
				foreach (Match match in matches)
				{
					var actual = match.Groups["stuff"].Value;
					var expected = System.Threading.Thread.CurrentThread.CurrentCulture.TextInfo.ToTitleCase(actual);
					if (!actual.Equals(expected))
					{
						var message = string.Format("\"{0}\" must be \"{1}\" at line {2}", actual, expected, lineNumber);
						errors.Add(message);
					}
				}

				matches = Regex.Matches(line, "<!--(?<stuff>@EndIf)", RegexOptions.IgnoreCase);
				foreach (Match match in matches)
				{
					var actual = match.Groups["stuff"].Value;
					var expected = "@EndIf";
					if (!actual.Equals(expected))
					{
						var message = string.Format("\"{0}\" must be \"{1}\" at line {2}", actual, expected, lineNumber);
						errors.Add(message);
					}
				}

				content.AppendFormat("{0,4}:\t{1}", lineNumber, line);
				content.AppendLine();
			}
			reader.Close();

			return ReportErrors(errors, template, content);
		}
	}

	private bool CheckIf(TemplateFile template)
	{
		using (var reader = new System.IO.StreamReader(template.TemplateFileInfo.FullName))
		{
			string line;
			var ifLevel = 0;
			var lineNumber = 0;
			var errors = new List<string>();
			var errorLineNumber = -1;
			var content = new StringBuilder();
			while ((line = reader.ReadLine()) != null)
			{
				lineNumber++;
				line = Regex.Replace(line, "<!--@(?<keyword>If|Else|EndIf)", m =>
				{
					var keyword = m.Groups["keyword"].Value;
					if (keyword == "If")
					{
						ifLevel += 1;
					}
					var result = string.Format("{0}[{1}]", m.Value, ifLevel);
					if (keyword == "EndIf")
					{
						ifLevel -= 1;
					}
					return m.Value; //result;
				});
				if (ifLevel < 0 && errorLineNumber < 0)
				{
					errorLineNumber = lineNumber;
					content.AppendFormat("{0,4}:\t[[strong]]{1}[[/strong]]", lineNumber, line);
				}
				else
				{
					content.AppendFormat("{0,4}:\t{1}", lineNumber, line);
				}
				content.AppendLine();
			}
			reader.Close();

			if (ifLevel != 0)
			{
				errors.Add(string.Format("Missing @{0} at {1}", (ifLevel > 0 ? "EndIf" : "If"), (errorLineNumber > 0) ? "line " + errorLineNumber : "end of file"));
			}

			return ReportErrors(errors, template, content);
		}
	}

	private bool ReportErrors(List<string> errors, TemplateFile template, StringBuilder content)
	{
		return ReportErrors(errors, template, content.ToString());
	}

	private bool ReportErrors(List<string> errors, TemplateFile template, string content)
	{
		if (errors.Count > 0)
		{
			var templateUrl = template.TemplateName;
			Write("<fieldset>");
			Write("<legend>{0}</legend>", templateUrl);
			foreach (var error in errors)
			{
				Write("<div class='error'>{0}</div>", HtmlEncode(error));
			}

			var templateLocation = template.Location;

			// if (!Dynamicweb.Base.DWAssemblyVersionInformation().StartsWith("8.3")) {
			// 	templateLocation = Regex.Replace(templateLocation, "^/Files/", "", RegexOptions.IgnoreCase);
			// }

			if (template.TemplateFileInfo.FullName.StartsWith(Server.MapPath("~/Files/Templates/")))
			{
				var editor = "FileManager_FileEditorV2.aspx";
				// editor = "Simple.aspx";
				var editUrl = string.Format("{0}://{1}/Admin/Filemanager/FileEditor/{2}?Folder={3}&amp;File={4}",
																		Request.Url.Scheme, Request.Url.Host, editor,
																		UrlEncode(templateLocation), UrlEncode(template.Name));
				Write("<div class='edit'><a target='edittemplate' href='{0}'>Edit template ({1})</a></div>", editUrl, templateUrl);
			}

			if (verbose)
			{
				Write("<hr/>");
				Write("<pre>{0}</pre>", Regex.Replace(HtmlEncode(content), @"\[{2,}(/?)([^\]]+)\]{2,}", "<$1$2>"));
			}
			Write("</fieldset>");
		}

		return errors.Count == 0;
	}

	private static string HtmlEncode(object o)
	{
		return Server.HtmlEncode(o.ToString());
	}

	private static string UrlEncode(object o)
	{
		return Server.UrlEncode(o.ToString());
	}

	private static HttpServerUtility Server
	{
		get
		{
			return System.Web.HttpContext.Current.Server;
		}
	}

	private void Write(string s)
	{
		Response.Write(s);
	}

	private void WriteLine()
	{
		Write("\n");
	}

	private void WriteLine(string s)
	{
		Write(s);
		Write("\n");
	}

	private void Write(string format, params object[] args)
	{
		Write(string.Format(format, args));
	}

	private void WriteLine(string format, params object[] args)
	{
		Write(format, args);
		Write("\n");
	}

	private void Write(object o)
	{
		Write(o.ToString());
	}

	private void WriteLine(object o)
	{
		Write(o);
		Write("\n");
	}

	private DirectoryInfo _templateDirectory = null;

	private DirectoryInfo TemplateDirectory
	{
		get
		{
			if (_templateDirectory == null)
			{
				var directory = new DirectoryInfo(Server.MapPath("~/Files/Templates/"));

				var request = System.Web.HttpContext.Current.Request;
				if (request["directory"] != null && Directory.Exists(request["directory"]))
				{
					directory = new DirectoryInfo(request["directory"]);
				}
				_templateDirectory = directory;
			}
			return _templateDirectory;
		}
	}

	private TemplateFileCollection GetTemplateFiles()
	{
		var collection = new TemplateFileCollection();
		GetTemplateFiles(TemplateDirectory, collection);
		return collection;
	}

	private void GetTemplateFiles(DirectoryInfo directory, TemplateFileCollection collection)
	{
		Regex filter = new Regex(".");
		if (Request["filter"] != null)
		{
			try
			{
				filter = new Regex(Request["filter"]);
			}
			catch { }
		}
		foreach (var file in TemplateFile.GetTemplateFiles(directory.FullName))
		{
			var includeTemplate = true;
			if (file.FullName.IndexOf("parsed") > -1)
			{
				includeTemplate = false;
			}
			if (filter != null && !filter.IsMatch(file.FullName))
			{
				includeTemplate = false;
			}
			if (includeTemplate)
			{
				collection.Add(file);
			}
		}
		foreach (var dir in directory.GetDirectories())
		{
			GetTemplateFiles(dir, collection);
		}
	}

	private static string GetTemplateLocation(string path)
	{
		var fileInfo = new FileInfo(path);
		var baseDirectory = Server.MapPath("~/Files/Templates/");
		var url = fileInfo.FullName;
		if (fileInfo.FullName.StartsWith(baseDirectory))
		{
			url = fileInfo.FullName.Substring(baseDirectory.Length, fileInfo.FullName.Length - baseDirectory.Length);
		}
		return url.Replace('\\', '/');
	}

	private HttpContext context;
	private HttpRequest _request;
	private HttpResponse _response;

	private HttpRequest Request
	{
		get
		{
			return _request ?? System.Web.HttpContext.Current.Request;
		}
	}

	private HttpResponse Response
	{
		get
		{
			return _response ?? System.Web.HttpContext.Current.Response;
		}
	}

	private void Initialize(HttpContext context)
	{
		this.context = context;
		_request = context.Request;
		_response = context.Response;
	}

	public bool IsReusable
	{
		get
		{
			return false;
		}
	}
}
